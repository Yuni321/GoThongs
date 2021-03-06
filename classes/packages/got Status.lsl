#define USE_EVENTS
//#define DEBUG DEBUG_UNCOMMON
#include "got/_core.lsl"

#define saveFlags() \
if(SFp != SF){ \
	raiseEvent(StatusEvt$flags, llList2Json(JSON_ARRAY, [SF, SFp])); \
	SFp = SF; \
}	

#define maxHP() ((DEFAULT_DURABILITY+fmMHn)*fmMH)
#define maxMana() ((DEFAULT_MANA+fmMMn)*fmMM)
#define maxArousal() ((DEFAULT_AROUSAL+fmMAn)*fmMA)
#define maxPain() ((DEFAULT_PAIN+fmMPn)*fmMP)

#define TIMER_REGEN "a"
#define TIMER_BREAKFREE "b"
#define TIMER_INVUL "c"
#define TIMER_CLIMB_ROOT "d"
#define TIMER_COMBAT "e"
#define TIMER_COOP_BREAKFREE "f"

#define TIME_SOFTLOCK 4		// Arousal/Pain softlock lasts 3 sec

#define updateCombatTimer() multiTimer([TIMER_COMBAT, "", StatusConst$COMBAT_DURATION, FALSE])

integer BFL = 1;
#define BFL_NAKED 1				// 
#define BFL_CLIMB_ROOT 4		// Ended climb, root for a bit
#define BFL_STATUS_QUEUE 0x10		// Send status on timeout
#define BFL_STATUS_SENT 0x20		// Status sent
#define BFL_AVAILABLE_BREAKFREE 0x40
#define BFL_CHALLENGE_MODE 0x80
#define BFL_QTE 0x100			// In a quicktime event
#define BFL_SOFTLOCK_AROUSAL 0x200	// Arousal will not regenerate
#define BFL_SOFTLOCK_PAIN 0x400		// Pain will not regenerate


// Cache
integer PC;							// Pre constants
integer PF;							// pre flags

integer TEAM_D = TEAM_PC;			// This is the team set by the HUD itself, can be overridden by fxT
integer TEAM = TEAM_PC; 			// This is team out

// Constant
integer LV = 1;	// Player level

// Effects
integer SF = 0; 	// Status flags
integer SFp = 0;	// Sttus flags pre
#define coop_player llList2Key(PLAYERS, 1)

integer GF;	// Genital flags

// FX
integer FXF = 0;				// FX flags
float paDT = 1; 				// damage taken modifier (only from PASSIVES)
list fmDT;						// [int playerID, float amount] From ACTIVEs 0 is wildcard
float fmMR = 1;					// mana regen
float fmAT = 1;					// Arousal taken
float fmPT = 1;					// Pain taken
float paHT = 1;					// Healing taken from passives
list fmHT;						// healing taken from actives [int playerID, float amount] From ACTIVE. 0 is wildcard
float fmHR = 1;					// HP regen
float fmPR = 1;					// Pain regen
float fmAR = 1;					// Arousal regen

float fmMH = 1;					// max health multiplier
integer fmMHn = 0;				// Max health adder
float fmMM = 1;					// max mana multiplier
integer fmMMn = 0;				// max mana adder
float fmMA = 1;					// max arousal multi
integer fmMAn = 0;				// max arousal adder
float fmMP = 1;					// max pain multiplier
integer fmMPn = 0;				// max pain adder


list fxC; // Conversions, see got FXCompiler.lsl

integer fxT = -1;	// FX team

key rLV;	// root level
#define isChallenge() (llKey2Name(rLV) != "" && BFL&BFL_CHALLENGE_MODE)

list SDTM; 	// Spell damage taken mod [str packageName, key2int(caster), float modifier] Caster of 0 is a wild card

// Resources
float HP = DEFAULT_DURABILITY;
float MANA = DEFAULT_MANA;
float AROUSAL = 0; 
float PAIN = 0;

list OST; 				// Output status to
list PLAYERS;
list TG; 		// Targeting: (key)id, (int)flags

integer DIF = 1;	// 
#define difMod() ((1.+(llPow(2, (float)DIF*.7)+DIF*3)*0.1)-0.4)

// Toggle clothes
tClt(){

	// Show genitals
	integer show = (SF&(StatusFlag$dead|StatusFlag$raped)) || FXF&fx$F_SHOW_GENITALS;
	
    if(show && ~BFL&BFL_NAKED){
		BFL = BFL|BFL_NAKED;
        llRegionSayTo(llGetOwner(), 1, "jasx.setclothes Bits");
		ThongMan$dead(
			TRUE, 							// Hide thong
			!(FXF&fx$F_SHOW_GENITALS)	// But don't show particles or sound if this was an FX call
		);
    }
	
	else if(!show && BFL&BFL_NAKED){
		BFL = BFL&~BFL_NAKED;
        llRegionSayTo(llGetOwner(), 1, "jasx.setclothes Dressed");
		llSleep(1);
        llRegionSayTo(llGetOwner(), 1, "jasx.togglefolder Dressed/Groin, 0");
		ThongMan$dead(FALSE, FALSE); 
    }
	
}

// Runs conversion
// Returns conversion effects of a FXC$CONVERSION_* type
float rCnv( integer ty, float am ){

	integer i; float out = 1;
	integer isDetrimental = (
		(am < 0 && ~llListFindList([FXC$CONVERSION_HP, FXC$CONVERSION_MANA], [ty])) ||
		(am > 0 && ~llListFindList([FXC$CONVERSION_PAIN, FXC$CONVERSION_AROUSAL], [ty]))
	);
	
	list conversions = [FXC$CONVERSION_HP,FXC$CONVERSION_MANA,FXC$CONVERSION_AROUSAL,FXC$CONVERSION_PAIN];
	list resources = [0,0,0,0];
	
	
	for(i=0; i<count(fxC); ++i){
		integer conv = l2i(fxC, i);
		integer d = FXC$conversionNonDetrimental(conv);
		
		if( 
			FXC$conversionFrom(conv) == ty && 
			((!isDetrimental && d) || (isDetrimental && !d))
		){
			
			float mag = FXC$conversionPerc(conv)/100.;
			integer b = FXC$conversionTo(conv);
			if(!FXC$conversionDontReduce(conv))
				out*= 1-mag;
			
			float amt = am*mag*FXC$conversionMultiplier(conv);
			
			// Flips amt
			if(FXC$conversionInverse(conv))
				amt = -amt;
			
			integer ndx = llListFindList(conversions, [b]);
			resources = llListReplaceList(resources, [l2f(resources, ndx)+amt], ndx, ndx);
		}
	}
	
	
	if(l2f(resources, 0))
		aHP(l2f(resources,0), "", 0, FALSE, TRUE, "");
	if(l2f(resources, 1))
		aMP(l2f(resources, 1), "", 0, TRUE, "");
	if(l2f(resources, 2))
		aAR(-l2f(resources, 2), "", 0, TRUE, "");
	if(l2f(resources, 3))
		aPP(-l2f(resources, 3), "", 0, TRUE, "");	
	
	return out;
}


// Returns TRUE if changed
// Adds HP: amount, spellName, flags, isRegen, is conversion
aHP( float am, string sn, integer fl, integer re, integer iCnv, key atkr ){

    if( 
		SF&StatusFlag$dead || 
		(SF&StatusFlag$cutscene && am<0 && ~fl&SMAFlag$OVERRIDE_CINEMATIC) 
	)return;
		
    float pre = HP;
    am*=spdmtm(sn, atkr);
		
	if(fl&SMAFlag$IS_PERCENTAGE)
		am*=maxHP();
	
    else if(am<0){
	
		// Damage taken multiplier
		float fmdt = 1;
		integer pos = llListFindList(llList2ListStrided(fmDT, 0,-1,2), (list)0);
		if( ~pos )
			fmdt *= l2f(fmDT, pos*2+1);
		if( ~(pos = llListFindList(llList2ListStrided(fmDT, 0,-1,2), (list)key2int(atkr))) )
			fmdt *= l2f(fmDT, pos*2+1);

		
		am*= 
			(1+((SF&StatusFlag$pained)/StatusFlag$pained)*.1)*
			(1+((SF&StatusFlag$aroused)/StatusFlag$aroused)*.1)*
			fmdt*paDT*
			difMod()
		;
		
		raiseEvent(StatusEvt$hurt, llRound(am));
		updateCombatTimer();
		
    }
	// Healing
	else if( !re ){
		
		// Healing taken multiplier
		float fmht = 1;
		integer pos = llListFindList(llList2ListStrided(fmHT, 0,-1,2), (list)0);
		if( ~pos )
			fmht *= l2f(fmHT, pos*2+1);
		if( ~(pos = llListFindList(llList2ListStrided(fmHT, 0,-1,2), (list)key2int(atkr))) )
			fmht *= l2f(fmHT, pos*2+1);
		am*= fmht*paHT;
		
	}
		
	// Run conversions
	if( !iCnv && ~fl&SMAFlag$IS_PERCENTAGE )
		am *= rCnv(FXC$CONVERSION_HP, am);
	
    HP += am;
    if( HP <= 0 ){
	
		HP = 0;
		
		// Death was prevented by fx$F_NO_DEATH
		if( FXF&fx$F_NO_DEATH ){
			if(pre != HP)
				raiseEvent(StatusEvt$death_hit, "");
		}
		else
			onDeath( "" );
			
		
    }else{
	
        if( HP > maxHP() )
			HP = maxHP();
        
		if( SF&StatusFlag$dead ){
			// REVIVED HANDLED HERE
			
			// Send to level here, counts as a loss
			
            SF = SF&~StatusFlag$dead;
			SF = SF&~StatusFlag$raped;
			SF = SF&~StatusFlag$coopBreakfree;
			
            raiseEvent(StatusEvt$dead, 0);
            Rape$end();
            AnimHandler$anim("got_loss", FALSE, 0, 0, 0);
            tClt();
			
			
			multiTimer([TIMER_BREAKFREE]);
			GUI$toggleLoadingBar((string)LINK_ROOT, FALSE, 0);
			GUI$toggleQuit(FALSE);
			
        }
		
    }

}

// add MP
aMP( float am, string sn, integer flags, integer iCnv, key atkr ){

    if( 
		SF&StatusFlag$dead || 
		(SF&StatusFlag$cutscene && am<0 && ~flags&SMAFlag$OVERRIDE_CINEMATIC) 
	)return;
	
	float in = am;
    float pre = MANA;
    am*=spdmtm(sn, atkr);
	if( flags&SMAFlag$IS_PERCENTAGE )
		am*=maxMana();
	// Run conversions
	else if( !iCnv )
		am*=rCnv(FXC$CONVERSION_MANA, am);

	MANA += am;
    if( MANA<=0 )
		MANA = 0;
    else if( MANA > maxMana() )
		MANA = maxMana();
		
	
}

// Add arousal
aAR( float am, string sn, integer flags, integer iCnv, key atkr ){

    if( 
		SF&StatusFlag$dead || 
		(SF&StatusFlag$cutscene && am>0 && ~flags&SMAFlag$OVERRIDE_CINEMATIC) 
	)return;
	
    float pre = AROUSAL;    
    am*=spdmtm(sn, atkr);
	
	if( flags&SMAFlag$IS_PERCENTAGE )
		am*=maxArousal();
    else if( am>0 )
		am*=fmAT;
	
	if( flags&SMAFlag$SOFTLOCK ){
		
		BFL = BFL|BFL_SOFTLOCK_AROUSAL;
		multiTimer(["SL:"+(str)BFL_SOFTLOCK_AROUSAL, "", TIME_SOFTLOCK, 0]);
		
	}
	
	// Run conversions
	if(!iCnv)
		am*=rCnv(FXC$CONVERSION_AROUSAL, am);
	
    AROUSAL += am;
    if(AROUSAL<=0)AROUSAL = 0;
    
	if( AROUSAL >= maxArousal() ){
	
        AROUSAL = maxArousal();
        if(~SF&StatusFlag$aroused){
            SF = SF|StatusFlag$aroused;
            llTriggerSound("d573fb93-d83e-c877-740f-6c28498668b8", 1);
        }
		
    }
	else if( SF&StatusFlag$aroused )
        SF = SF&~StatusFlag$aroused;
    
}

// add Pain
aPP( float am, string sn, integer flags, integer iCnv, key atkr ){
    
	if(
		SF&StatusFlag$dead || 
		(SF&StatusFlag$cutscene && am>0 && ~flags&SMAFlag$OVERRIDE_CINEMATIC)
	)return;
	
    float pre = PAIN;
    am*=spdmtm(sn, atkr);
	if( flags&SMAFlag$IS_PERCENTAGE )
		am*=maxPain();
    else if( am>0 )
		am*=fmPT;
		
	if( flags&SMAFlag$SOFTLOCK ){
		
		BFL = BFL|BFL_SOFTLOCK_PAIN;
		multiTimer(["SL:"+(str)BFL_SOFTLOCK_PAIN, "", TIME_SOFTLOCK, 0]);
		
	}
    
	// Run conversions
	if(!iCnv && ~flags&SMAFlag$IS_PERCENTAGE)
		am*=rCnv(FXC$CONVERSION_PAIN, am);	
	
	PAIN += am;
    if(PAIN<=0)PAIN = 0;
    
	if(PAIN >= maxPain()){
        PAIN = maxPain();
        if(~SF&StatusFlag$pained){
            SF = SF|StatusFlag$pained;
            llTriggerSound("4db10248-1e18-63d7-b9d5-01c6c0d8a880", 1);
        }
    }else if(SF&StatusFlag$pained)
        SF = SF&~StatusFlag$pained;

}

// sn = package name, c = caster
float spdmtm( string sn, key c ){

    if( !isset(sn) )
		return 1;
    
	integer cn = key2int(c);
	
	float out = 1;
	
	integer i;
    for( i=0; i<llGetListLength(SDTM); i+=3 ){
	
        if( 
			llList2String(SDTM, i) == sn && 
			( !l2i(SDTM, i+1) || l2i(SDTM, i+1) == cn ) 
		){
            
			float nr = llList2Float(SDTM, i+2);
            if( nr <0 )
				return 0;
            out*= (1+nr);
			
        }
		
    }
	
	return out;
	
}


onDeath( string customAnim ){

	// Player dead already
	if(SF&StatusFlag$dead)
		return;
	
	// DEATH HANDLED HERE
	SpellMan$interrupt(TRUE);
	SF = SF|StatusFlag$dead;
	BFL = BFL&~BFL_AVAILABLE_BREAKFREE;
	
	gotLevelData$died();
	
	OS( TRUE );
	raiseEvent(StatusEvt$dead, 1);
	AnimHandler$anim("got_loss", TRUE, 0, 0, 0);
	
	tClt();
	
	float dur = 20;
	if( isChallenge() ){
	
		dur = 90;
		if(SF & StatusFlag$boss_fight)
			dur = 0;
		else
			multiTimer([TIMER_COOP_BREAKFREE, "", 20, FALSE]);
			
	}
	if(dur){
	
		multiTimer([TIMER_BREAKFREE, "", dur, FALSE]);
		GUI$toggleLoadingBar((string)LINK_ROOT, TRUE, dur);
		
	}
	
	// If customAnim is set, use that
	if( customAnim )
		return Bridge$fetchRape((str)LINK_ROOT, customAnim);
	
	// Otherwise fetch one
	Status$monster_rapeMe();
	Rape$activateTemplate();
	

}

onEvt( string script, integer evt, list data ){
    if(script == "#ROOT"){
        if(evt == RootEvt$players){
            PLAYERS = data;
        }
        else if(evt == evt$TOUCH_START){
            if(~SF&StatusFlag$dead && ~SF&StatusFlag$raped)return;
            integer prim = llList2Integer(data, 0);
            string ln = llGetLinkName(prim);
            if(ln == "QUIT"){
                Status$fullregen();
            }
        }
		else if(evt == RootEvt$level){
		
			rLV = llList2String(data, 0);
			BFL = BFL&~BFL_CHALLENGE_MODE;
			if( l2i(data, 1) )
				BFL = BFL|BFL_CHALLENGE_MODE;
			
		}
		else if(evt == evt$BUTTON_PRESS && l2i(data, 0)&CONTROL_UP && BFL&BFL_AVAILABLE_BREAKFREE && SF&StatusFlag$dead){
			Status$fullregen();
		}
        // Force update on targeting self, otherwise it requests
        else if( evt == RootEvt$targ && llList2Key(data, 0) == llGetOwner() )
			OS( TRUE );
			
    }
	
	else if(script == "got SpellMan"){
	
        if(evt == SpellManEvt$cast || evt == SpellManEvt$interrupted || evt == SpellManEvt$complete){
		
            if(evt == SpellManEvt$cast){
			
                // At least 1 sec to count as a cast
                if(i2f(llList2Float(data, 0))<1)return;
                SF = SF|StatusFlag$casting;
				
            }
            else 
				SF = SF&~StatusFlag$casting;
				
            OS(TRUE);
			
        }
		
    }
	
	else if(script == "got Bridge"){
		if(evt == BridgeEvt$userDataChanged){
			Status$setDifficulty(l2i(data, 4));
		}
		else if(evt == BridgeEvt$thong_initialized)
			tClt();
        
    }
	
    else if( script == "got Rape" ){
	
        if( evt == RapeEvt$onStart || evt == RapeEvt$onEnd ){
		
            if( evt == RapeEvt$onStart ){
			
                SF = SF|StatusFlag$raped;
                OS(TRUE);
				
            }
            else if( SF&StatusFlag$raped ){
			
                SF = SF&~StatusFlag$raped; 
				Status$fullregen();
				
            }
            AnimHandler$anim("got_loss", FALSE, 0, 0, 0);
        }
    }
	
	else if( script == "jas Primswim" ){
	
		if( evt == PrimswimEvt$onWaterEnter )
			SF = SF|StatusFlag$swimming;
		else if( evt == PrimswimEvt$onWaterExit )
			SF = SF&~StatusFlag$swimming;
		OS( TRUE );
		
	}
	
	else if( script == "jas Climb" ){
	
		if( evt == ClimbEvt$start )
			SF = SF|StatusFlag$climbing;
		else if( evt == ClimbEvt$end ){
		
			SF = SF&~StatusFlag$climbing;
			integer f = (int)j(llList2String(data,1), 0);
			if( f&StatusClimbFlag$root_at_end ){
				
				multiTimer([TIMER_CLIMB_ROOT, "", 1.5, FALSE]);
				BFL = BFL|BFL_CLIMB_ROOT;
				
			}
			
		}
		OS(TRUE);
		
	}
	
	else if(script == "jas RLV" && (evt == RLVevt$cam_set || evt == RLVevt$cam_unset)){
		
		SF = SF&~StatusFlag$cutscene;
		if( evt == RLVevt$cam_set )
			SF = SF|StatusFlag$cutscene;
		OS(TRUE);
		
	}
	
	else if( script == "got Evts" && evt == EvtsEvt$QTE ){
	
		BFL = BFL&~BFL_QTE;
		if(l2i(data, 0))
			BFL = BFL|BFL_QTE;
		OS(TRUE);
		
	}
}



float cH;		// cache Health
float cM;		// cache Mana
float cA;		// cache Arousal
float cP;		// cache Pain

// output stats
// ic = ignore cache check
OS( int ic ){ 

	if( !ic && cH == HP && cM == MANA && cA == AROUSAL && cP == PAIN )
		return;
	
	cH = HP;
	cM = MANA;
	cA = AROUSAL;
	cP = PAIN;
	
	// Check team
	integer t = fxT;
	
	if(t == -1)
		t = TEAM_D;
		
	integer pre = TEAM;

	// GUI
	// Status is on cooldown and team has not changed
	if(BFL&BFL_STATUS_SENT && pre == t){
		// We need to output status once the timer fades
		BFL = BFL|BFL_STATUS_QUEUE;
	}
	else{
		raiseEvent(StatusEvt$resources, llList2Json(JSON_ARRAY,[
			(int)HP, (int)maxHP(), 
			(int)MANA, (int)maxMana(), 
			(int)AROUSAL, (int)maxArousal(), 
			(int)PAIN,(int)maxPain(),
			HP/maxHP()
		]));

		BFL = BFL|BFL_STATUS_SENT;
		multiTimer(["_", "", 0.25, FALSE]);
	}
	
	// Always keep description up to date
	if(HP>maxHP())
		HP = maxHP();
	if(MANA>maxMana())
		HP = maxHP();
		
	// int is 0000000 << 21 hp_perc, 0000000 << 14 mana_perc, 0000000 << 7 arousal_perc, 0000000 pain_perc 
	string data = (string)(
		(llRound(HP/maxHP()*127)<<21) |
		(llRound(MANA/maxMana()*127)<<14) |
		(llRound(AROUSAL/maxArousal()*127)<<7) |
		llRound(PAIN/maxPain()*127)
	);
	llSetObjectDesc(data+"$"+(str)SF+"$"+(str)FXF+"$"+(str)GF+"$"+(str)t);
	
	// Team change goes after because we need to update description first
	if(pre != t){
		TEAM = t;
		
		raiseEvent(StatusEvt$team, TEAM);
		runOnPlayers(targ,
			if(targ == llGetOwner())
				targ = (str)LINK_ROOT;
			Root$forceRefresh(targ, llGetKey());
		)
	}
	
	
    integer controls = CONTROL_ML_LBUTTON|CONTROL_UP|CONTROL_DOWN;
    if(FXF&fx$F_STUNNED || BFL&BFL_QTE || (SF&(StatusFlag$dead|StatusFlag$climbing|StatusFlag$loading|StatusFlag$cutscene) && ~SF&StatusFlag$raped)){
        controls = controls|CONTROL_FWD|CONTROL_BACK|CONTROL_LEFT|CONTROL_RIGHT|CONTROL_ROT_LEFT|CONTROL_ROT_RIGHT;
	}
    if(FXF&fx$F_ROOTED || (SF&(StatusFlag$casting|StatusFlag$swimming) && ~FXF&fx$F_CAST_WHILE_MOVING) || BFL&BFL_CLIMB_ROOT){
		controls = controls|CONTROL_FWD|CONTROL_BACK|CONTROL_LEFT|CONTROL_RIGHT;
	}
	if(FXF&fx$F_NOROT){
		controls = controls|CONTROL_ROT_LEFT|CONTROL_ROT_RIGHT;
	}
	
	
    if(PC != controls){
        PC = controls;
        Root$statusControls(controls);
    }
    if(PF != SF){
        PF = SF;
        saveFlags();
    }
}

timerEvent(string id, string data){
	
    if(id == TIMER_REGEN){
		integer inCombat = (SF&StatusFlags$combatLocked)>0;
		
		integer ainfo = llGetAgentInfo(llGetOwner());

		#define DEF_MANA_REGEN 0.025
		#define DEF_HP_REGEN 0.015
		#define DEF_PAIN_REGEN 0.05
		#define DEF_AROUSAL_REGEN 0.05
		
		integer n; // Used to only update if values have changed
			
		float add = (maxMana()*DEF_MANA_REGEN)*fmMR;
        if( add > 0 )
			aMP(add, "", 0, FALSE, llGetOwner());
		
		// The following only regenerate out of combat
		if( !inCombat ){

			if(DEF_HP_REGEN*fmHR>0)
				aHP(fmHR*DEF_HP_REGEN, "", SMAFlag$IS_PERCENTAGE, TRUE, FALSE, llGetOwner());
			if( DEF_PAIN_REGEN*fmPR>0 && ~BFL&BFL_SOFTLOCK_PAIN )
				aPP(-fmPR*DEF_PAIN_REGEN, "", SMAFlag$IS_PERCENTAGE, FALSE, llGetOwner());
			if( DEF_AROUSAL_REGEN*fmAR>0 && ~BFL&BFL_SOFTLOCK_AROUSAL )
				aAR(-fmAR*DEF_AROUSAL_REGEN, "", SMAFlag$IS_PERCENTAGE, FALSE, llGetOwner());
			
		}
		
		OS(FALSE);
		
	}
    else if(id == "_"){
	
		BFL = BFL&~BFL_STATUS_SENT;
		if(BFL&BFL_STATUS_QUEUE){
		
			BFL = BFL&~BFL_STATUS_QUEUE;
			OS(TRUE);
			
		}
		
    }
	else if(id == TIMER_BREAKFREE){
		// Show breakfree button
		GUI$toggleLoadingBar((string)LINK_ROOT, FALSE, 0);
		GUI$toggleQuit(TRUE);
		BFL = BFL|BFL_AVAILABLE_BREAKFREE;
	}
	else if(id == TIMER_INVUL){
	
		SF = SF&~StatusFlag$invul;
		OS( TRUE );
		
	}
	else if( id == TIMER_CLIMB_ROOT ){
	
		BFL = BFL&~BFL_CLIMB_ROOT;
		OS( TRUE );
		
	}
	else if(id == TIMER_COMBAT){
	
		SF = SF&~StatusFlag$combat;
		saveFlags();
		
	}
	else if(id == TIMER_COOP_BREAKFREE){
		llRezAtRoot("BreakFree", llGetPos(), ZERO_VECTOR, ZERO_ROTATION, 1);
		SF = SF|StatusFlag$coopBreakfree;
		saveFlags();
	}
	
	else if( startsWith(id, "SL:") )
		BFL = BFL&~(int)llGetSubString(id, 3, -1);
	
}


default 
{
    state_entry(){
	
		PLAYERS = [(string)llGetOwner()];
        OS( TRUE );
        Status$fullregen();
        multiTimer([TIMER_REGEN, "", 1, TRUE]);
        llRegionSayTo(llGetOwner(), 1, "jasx.settings");
        tClt();
		llOwnerSay("@setdebug_RenderResolutionDivisor:0=force");
		
    }
    
    timer(){
        multiTimer([]);
    }
    
	#define LM_PRE \
	if(nr == TASK_REFRESH_COMBAT){ \
		integer combat = SF&StatusFlag$combat; \
		SF = SF|StatusFlag$combat; \
		updateCombatTimer(); \
		if(!combat)saveFlags(); \
	} \
	if(nr == TASK_FX){ \
		list data = llJson2List(s); \
        integer pre = FXF; \
		FXF = llList2Integer(data, 0); \
		\
		integer divisor = 0; \
		if(FXF&fx$F_BLURRED){ \
			divisor = 8; \
		} \
		if((pre&fx$F_BLURRED) != (FXF&fx$F_BLURRED)){ \
			llOwnerSay("@setdebug_renderresolutiondivisor:"+(string)divisor+"=force"); \
		}\
		\
        paDT = i2f(l2f(data, FXCUpd$DAMAGE_TAKEN)); \
        fmMR = i2f(l2f(data, FXCUpd$MANA_REGEN)); \
		 \
		fmPT = i2f(l2f(data,FXCUpd$PAIN_MULTI)); \
		fmAT = i2f(l2f(data,FXCUpd$AROUSAL_MULTI)); \
		 \
		float perc = HP/maxHP(); \
		float mperc = MANA/maxMana(); \
		fmMH = i2f(l2f(data, FXCUpd$HP_MULTIPLIER)); \
		fmMHn = llList2Integer(data, FXCUpd$HP_ADD); \
		fmMM = i2f(l2f(data, FXCUpd$MANA_MULTIPLIER)); \
		fmMMn = llList2Integer(data, FXCUpd$MANA_ADD); \
		fmMA = i2f(l2f(data, FXCUpd$AROUSAL_MULTIPLIER)); \
		fmMAn = llList2Integer(data, FXCUpd$AROUSAL_ADD); \
		fmMP = i2f(l2f(data, FXCUpd$PAIN_MULTIPLIER)); \
		fmMPn = llList2Integer(data, FXCUpd$PAIN_ADD); \
		fmHR = i2f(l2f(data, FXCUpd$HP_REGEN)); \
		fmPR = i2f(l2f(data, FXCUpd$PAIN_REGEN)); \
		fmAR = i2f(l2f(data, FXCUpd$AROUSAL_REGEN)); \
		paHT = i2f(l2f(data, FXCUpd$HEAL_MOD)); \
		fxT = l2i(data, FXCUpd$TEAM); \
		fxC = llJson2List(l2s(data, FXCUpd$CONVERSION)); \
		HP = maxHP()*perc; \
		MANA = maxMana()*mperc; \
        OS( TRUE ); \
		tClt(); \
    } \
	
    // This is the standard linkmessages
    #include "xobj_core/_LM.lsl"  
    /*
        Included in all these calls:
        METHOD - (int)method  
        PARAMS - (var)parameters 
        SENDER_SCRIPT - (var)parameters
        CB - The callback you specified when you sent a task 
    */ 
    
    // Here's where you receive callbacks from running methods
    if(method$isCallback){
        return;
    }
    
    if(id == ""){
        
		if(METHOD == StatusMethod$setDifficulty){
			
			integer pre = DIF;
			DIF = llList2Integer(PARAMS, 0);
			raiseEvent(StatusEvt$difficulty, DIF);
			
			if(DIF != pre){
				list names = [
					"Casual", 
					"Normal", 
					"Hard", 
					"Very Hard", 
					"Brutal", 
					"Bukakke"
				];
				
				Alert$freetext(LINK_THIS, "Difficulty set to "+llList2String(names, DIF), TRUE, TRUE);
			}
		
		}
		else if(METHOD == StatusMethod$setSex){
            GF = (integer)method_arg(0);
			raiseEvent(StatusEvt$genitals, GF);
        }
    }

	if(METHOD == StatusMethod$debug && method$byOwner){
		qd(
			"HP: "+(str)HP+"/"+(str)maxHP()+" | "+
			"Mana: "+(str)MANA+"/"+(str)maxMana()+" | "+
			"Ars: "+(str)AROUSAL+"/"+(str)maxArousal()+" | "+
			"Pain: "+(str)PAIN+"/"+(str)maxPain()
		);
	}
	
	if(METHOD == StatusMethod$kill){
	
		HP = 0;
		onDeath( method_arg(0) );
		
	}
	
	if(METHOD == StatusMethod$batchUpdateResources){
	
		// note: Attacker is trimmed to the first 8 bytes of your key
		string attacker = method_arg(0);
		PARAMS = llDeleteSubList(PARAMS, 0, 0);
	
		while(PARAMS){
		
			integer type = l2i(PARAMS, 0);
			integer len = l2i(PARAMS, 1);

			list data = llList2List(PARAMS, 2, 2+len-1);		// See SMBUR$* at got Status
			PARAMS = llDeleteSubList(PARAMS, 0, 2+len-1);
			float am = i2f(llList2Float(data, 0));	
			string name = l2s(data, 1);					// Spell name
			integer flags = l2i(data, 2);				// Spell flags

			// Apply
			if(type == SMBUR$durability)
				aHP(am, name, flags, FALSE, FALSE, attacker);
			else if(type == SMBUR$mana)
				aMP(am, name, flags, FALSE, attacker);
			else if(type == SMBUR$arousal)
				aAR(am, name, flags, FALSE, attacker);
			else if(type == SMBUR$pain)
				aPP(am, name, flags, FALSE, attacker);
		}
		OS( FALSE );
		
	}
	
    else if( METHOD == StatusMethod$setTargeting ){
		
		integer flags = llList2Integer(PARAMS, 0); 				// Target or untarget
		integer pos = llListFindList(TG, [(str)id]);		// See if already targeting
		integer remove;
		if( flags < 0 ){
			
			flags = llAbs(flags);
			remove = TRUE;
			
		}
		
		integer cur = l2i(TG, pos+1);
		
		// Remove from existing
		if( ~pos && remove )
			cur = cur&~flags;
		// Add either new or existing
		else if( 
			(~pos && !remove && (cur|flags) != flags ) ||
			( pos == -1 && !remove )
		)cur = cur|flags;
		// Cannot remove what does not exist
		else
			return;
		
		// Exists, update
		if( ~pos && cur )
			TG = llListReplaceList(TG, [cur], pos+1, pos+1);
		// Exists, delete
		else if( ~pos && !cur )
			TG = llDeleteSubList(TG, pos, pos+1);
		// Insert new
		else
			TG += [(str)id, cur];

		// Immediately send stats
		OS( TRUE );
		raiseEvent(StatusEvt$targeted_by, mkarr(TG));
		
	}
    
    else if(
		METHOD == StatusMethod$fullregen || 
		(METHOD == StatusMethod$coopInteract && SF&StatusFlag$coopBreakfree)
	){
				
		integer ignoreInvul = l2i(PARAMS, 0);
        Rape$end();
        
		if( SF&StatusFlag$dead && ! ignoreInvul ){
		
			SF = SF|StatusFlag$invul;
			OS(TRUE);
			multiTimer([TIMER_INVUL,"", 6, FALSE]);
			
		}
        HP = maxHP();
        MANA = maxMana();
        AROUSAL = 0;
        PAIN = 0;
        SF = SF&~StatusFlag$dead;
        SF = SF&~StatusFlag$raped;
        SF = SF&~StatusFlag$pained;
        SF = SF&~StatusFlag$aroused;
		SF = SF&~StatusFlag$coopBreakfree;
        raiseEvent(StatusEvt$dead, 0);
        
        AnimHandler$anim("got_loss", FALSE, 0, 0, 0);
        OS(TRUE);
        tClt();
		
		
		
		// Clear rape stuff
		multiTimer([TIMER_BREAKFREE]);
		GUI$toggleLoadingBar((string)LINK_ROOT, FALSE, 0);
		GUI$toggleQuit(FALSE);
    }
    else if(METHOD == StatusMethod$get){
        CB_DATA = [SF, FXF, floor(HP/maxHP()*100), floor(MANA/maxMana()*100), floor(AROUSAL/maxArousal()*100), floor(PAIN/maxPain()*100), GF, TEAM];
    }
    else if( METHOD == StatusMethod$spellModifiers ){
        
		SDTM = llJson2List(method_arg(0));
		fmDT = llJson2List(method_arg(1));
		fmHT = llJson2List(method_arg(2));
		
	}
    
	
    else if(METHOD == StatusMethod$outputStats)
        OS(TRUE);
		
    else if(METHOD == StatusMethod$loading){
	
		integer loading = (integer)method_arg(0);
		integer pre = SF;
		SF = SF&~StatusFlag$loading;
		if( loading )
			SF = SF|StatusFlag$loading;
		
		if( pre != SF ){
		
			integer divisor = 0;
			if( loading )
				divisor = 6;
			llOwnerSay("@setdebug_RenderResolutionDivisor:"+(string)divisor+"=force");
			OS(TRUE);
			
		}
		raiseEvent(StatusEvt$loading_level, id);
		
	}
	else if(METHOD == StatusMethod$debugOut){
		llOwnerSay(mkarr(([maxHP(), maxMana(), maxArousal(), maxPain()])));
	}
	else if( METHOD == StatusMethod$toggleBossFight ){
		
		integer on = (int)method_arg(0);
		if( 
			(on && SF&StatusFlag$boss_fight) || 
			(!on&&~SF&StatusFlag$boss_fight) 
		)return;
		
		if( on )
			SF = SF | StatusFlag$boss_fight;
		
		else{
			SF = SF &~ StatusFlag$boss_fight;
			/*
			if(SF & StatusFlag$dead)
				Status$fullregen();
			*/
		}
		saveFlags();
	}
    else if(METHOD == StatusMethod$setTeam){
	
		TEAM_D = llList2Integer(PARAMS, 0);
		OS(TRUE);
		
	} 
	
	else if( METHOD == StatusMethod$getTextureDesc )
		Evts$getTextureDesc(method_arg(0), id);
    
	
	if(METHOD == StatusMethod$coopInteract)
		raiseEvent(StatusEvt$interacted, (str)id);
	
	
    // Public code can be put here

    // End link message code
    #define LM_BOTTOM  
    #include "xobj_core/_LM.lsl"  
}
