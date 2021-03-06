#define EvtsMethod$cycleEnemy 1				// void - Get a nearby enemy
#define EvtsMethod$startQuicktimeEvent 2	// (int)numButtons, (float)preDelay, (str)callback - Starts a quick time event where you have to push numButtons random buttons. Sends a callback with the first arg being one of the below tasks and the CB specified. preDelay lets you delay before the event starts, useful when forcing avatars to sit on targets as that seems to raise a keypress event without pushing a key
	// Callback tasks [(int)task, (var)arg1...]
	#define EvtsEvt$QTE$APPLY 0					// (int)success - QTE task was executed
	#define EvtsEvt$QTE$BUTTON 1				// (int)success - QTE button was hit. Success = proper button was hit
	#define EvtsEvt$QTE$END 2					// (int)success - QTE has ended. Success = all buttons were hit
	
#define EvtsMethod$addTextureDesc 3	// pid, texture, desc, added, duration, stacks - Adds a spell icon
#define EvtsMethod$remTextureDesc 4	// (key)texture						
#define EvtsMethod$getTextureDesc 5	// (int)pos, (key)texture - Gets info about a spell by pos
#define EvtsMethod$stacksChanged 6	// (int)PID, (int)added, (float)duration, (int)stacks - Sent when stacks have changed.
	
#define EvtsEvt$QTE 1						// (int)numButtons - Quick time event, 0 for off

	
	

#define Evts$cycleEnemy() runMethod((string)LINK_SET, "got Evts", EvtsMethod$cycleEnemy, [], TNN)
#define Evt$startQuicktimeEvent(targ, numButtons, preDelay, callback) runMethod((str)targ, "got Evts", EvtsMethod$startQuicktimeEvent, [numButtons, preDelay], callback)

#define Evts$addTextureDesc(pid, texture, desc, added, duration, stacks) runMethod((string)LINK_ROOT, "got Evts", EvtsMethod$addTextureDesc, [pid, texture, desc, added, duration, stacks], TNN)
#define Evts$remTextureDesc(pid) runMethod((string)LINK_ROOT, "got Evts", EvtsMethod$remTextureDesc, [pid], TNN)
#define Evts$getTextureDesc(pid, player) runMethod((str)LINK_ROOT, "got Evts", EvtsMethod$getTextureDesc, [pid, player], TNN)
#define Evts$stacksChanged(pid, added, duration, stacks) runMethod((string)LINK_ROOT, "got Evts", EvtsMethod$stacksChanged, [pid, added, duration, stacks], TNN)
