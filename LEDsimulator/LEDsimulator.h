//
//  LEDsimulator.h
//  LEDsimulator
//
//  Created by Huib Verweij on 27-09-09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#include "AsyncSocket.h"
#include "StripeView.h"

#define PORT_NUMBER 55555
#define PROTOCOL_MSG_SIZE 7
#define READ_TIMEOUT -1
#define BUTTON_PRESSED_TAG 1

#define NUMBER_OF_LEDS 32
#define LEDBACKGROUNDCOLOR (169.0/255.0)

#define CMD_SETSTRIPE 16
#define CMD_SETROW 12
#define CMD_DEMO 254
#define CMD_FADEALLTOWHITE 22
#define CMD_FADEALLTOBLACK 21

@interface LEDsimulator : NSObject {
	IBOutlet NSTextField *status;
	IBOutlet NSBox *box;
	IBOutlet NSTextFieldCell *serverInfo;

	
	AsyncSocket *listenSocket;
	NSMutableArray *connectedSockets;
	
	BOOL isRunning;
	NSThread *server;
}

@property (assign) NSTextField *status;
@property (assign) NSTextFieldCell *serverInfo;

- (void)process_commands:(NSData *)command;
- (void)setStripe:(NSUInteger)stripe withColor:(NSColor *)color;
- (IBAction)buttonOnePressed:(id)sender;
- (IBAction)buttonTwoPressed:(id)sender;
- (void)updateSocketStatus:(AsyncSocket *)socket;
- (void)updateSocketStatusWithHost:(NSString *)host AndPort:(UInt16)port;
- (void)buttonPressed:(int)button;

@end
