#include "got/_core.lsl"

integer BFL;
#define BFL_RAPE_STARTED 1

list RAPE_ANIMS;
list RAPE_ATTACHMENTS;

timerEvent(string id, string data){
    
}

default 
{
    // Timer event
    timer(){multiTimer([]);}
    
    
    // This is the standard linkmessages
    #include "xobj_core/_LM.lsl" 
    /*
        Included in all these calls:
        METHOD - (int)method  
        PARAMS - (var)parameters 
        SENDER_SCRIPT - (var)parameters
        CB - The callback you specified when you sent a task 
    */ 
    
    if(method$isCallback){
        return;
    }
    
    if(method$internal){
        if(METHOD == RapeMethod$start){
            if(BFL&BFL_RAPE_STARTED)return;
            
            BFL = BFL|BFL_RAPE_STARTED;
            
            RAPE_ANIMS = llJson2List(method_arg(0));
            RAPE_ATTACHMENTS = llJson2List(method_arg(1));
            list sounds = llJson2List(method_arg(2));
            
            integer i;
            for(i=0; i<llGetListLength(RAPE_ATTACHMENTS); i++){
                llRezAtRoot(llList2String(RAPE_ATTACHMENTS, i), llGetPos()-<0,0,2>, ZERO_VECTOR, ZERO_ROTATION, 1);
            }
            for(i=0; i<llGetListLength(RAPE_ANIMS); i++)
                AnimHandler$anim(llList2String(RAPE_ANIMS, i), TRUE, 0);
            
            vector pos = llGetPos();
            vector ascale = llGetAgentSize(llGetOwner());
            list ray = llCastRay(pos, pos-<0,0,5>, [RC_REJECT_TYPES, RC_REJECT_PHYSICAL|RC_REJECT_AGENTS]);
            if(llList2Integer(ray,-1) == 1)
                pos = llList2Vector(ray, 1)+<0,0,ascale.z/2-.1>;
            
            
            rotation rot = llGetRootRotation();
            vector vrot = llRot2Euler(rot);
            vrot = <0,0,vrot.z>;
            
            RLV$cubeTask(([
                SupportcubeBuildTask(Supportcube$tSetPos, [pos]),
                SupportcubeBuildTask(Supportcube$tSetRot, [llEuler2Rot(vrot)]),
                SupportcubeBuildTask(Supportcube$tForceSit, [true])
            ]));
            
            raiseEvent(RapeEvt$onStart, "");
            if(~_statusFlags()&StatusFlag$inLevel)GUI$toggleQuit(TRUE);
        }
    }
    
    if(method$byOwner){
        
    }
    
    if(METHOD == RapeMethod$end){
        BFL = BFL&~BFL_RAPE_STARTED;
        
        list_shift_each(RAPE_ATTACHMENTS, val, 
            Attached$remove(val);
        )
        list_shift_each(RAPE_ANIMS, val,
            AnimHandler$anim(val, FALSE, 0);
        )
        
        raiseEvent(RapeEvt$onEnd, "");
        
        RLV$cubeTask([
            SupportcubeBuildTask(Supportcube$tForceUnsit, [])
        ]);
    }
    
    // Public code can be put here

    // End link message code
    #define LM_BOTTOM  
    #include "xobj_core/_LM.lsl"  
}
