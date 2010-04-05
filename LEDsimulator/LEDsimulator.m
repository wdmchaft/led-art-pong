//
//  LEDsimulator.m
//  LEDsimulator
//
//  Created by Huib Verweij on 27-09-09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "LEDsimulator.h"


@implementation LEDsimulator

@synthesize status;
@synthesize serverInfo;


- (id)init
{
	NSLog(@"LEDsimulator init starting\n");
	if((self = [super init]))
	{
		listenSocket = [[AsyncSocket alloc] initWithDelegate:self];
		connectedSockets = [[NSMutableArray alloc] initWithCapacity:1];
	}
	NSLog(@"LEDsimulator init done\n");
	return self;
}

- (void) awakeFromNib {
	NSLog(@"LEDsimulator awakeFromNib starting\n");
	[box setFillColor:[NSColor blackColor]];
	[self updateSocketStatus:nil];
	for (int i = 0; i < NUMBER_OF_LEDS ; i++) {
		NSRect frame = NSMakeRect(20+i*26.0, 10.0, 20.0, 20.0);
		StripeView *stripeView = [[StripeView alloc] initWithFrame:frame color:[NSColor colorWithCalibratedRed:LEDBACKGROUNDCOLOR green:LEDBACKGROUNDCOLOR blue:LEDBACKGROUNDCOLOR alpha:1.0]];
		[[box contentView] addSubview:stripeView];
		[stripeView release];
	}

	NSLog(@"LEDsimulator awakeFromNib done\n");
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	NSLog(@"Ready");
	
	// Advanced options - enable the socket to continue operations even during modal dialogs, and menu browsing
	[listenSocket setRunLoopModes:[NSArray arrayWithObject:NSRunLoopCommonModes]];
	
	
	NSError *error = nil;
	if(![listenSocket acceptOnPort:PORT_NUMBER error:&error])
	{
		NSLog(@"Error starting server: %@", error);
		return;
	}
	
	NSLog(@"Echo server started on port %hu", [listenSocket localPort]);
	
	[self updateSocketStatus:nil];
	
}

- (void)onSocket:(AsyncSocket *)sock didAcceptNewSocket:(AsyncSocket *)newSocket
{
	[connectedSockets addObject:newSocket];
}

- (void)onSocket:(AsyncSocket *)sock didConnectToHost:(NSString *)host port:(UInt16)port
{
	NSLog(@"Accepted client %@:%hu", host, port);
	[self updateSocketStatusWithHost:host AndPort:port];
	[sock readDataToLength:PROTOCOL_MSG_SIZE withTimeout:READ_TIMEOUT tag:0];
}


- (void)onSocket:(AsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag
{
	// NSLog(@"Received data %@ with tag:%@ on socket %@", [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease], tag, sock);
	[self process_commands:data];
	[sock readDataToLength:PROTOCOL_MSG_SIZE withTimeout:READ_TIMEOUT tag:0];
}

- (void)onSocket:(AsyncSocket *)sock willDisconnectWithError:(NSError *)err
{
	NSLog(@"Client Disconnected: %@:%hu", [sock connectedHost], [sock connectedPort]);
}

- (void)onSocketDidDisconnect:(AsyncSocket *)sock
{
	[connectedSockets removeObject:sock];
	[self updateSocketStatus:nil];
}



- (void)updateSocketStatus:(AsyncSocket *)socket {
	if (socket == nil) {
		if (listenSocket != nil) {
			if ([listenSocket isConnected]) {
				NSLog(@"listening on %@:%@.", [listenSocket localHost], [listenSocket localPort]);
				[status setStringValue:[NSString stringWithFormat:@"listening on %@:%@.", [listenSocket localHost], [listenSocket localPort]]];
			}
			else {
				NSLog(@"not listening yet");
				[status setStringValue:@"not listening yet"];
			}
		}
		else {
			[status setStringValue:@"initialising"];
		}

	}
	else {
		[status setStringValue: [NSString stringWithFormat:@"connected to %@:%@", [socket connectedHost], [socket connectedPort]]];
	}		
}


- (void)updateSocketStatusWithHost:(NSString *)host AndPort:(UInt16)port {
	[status setStringValue:[NSString stringWithFormat:@"listening on %@:%d.", host, port]];
}


- (void)process_commands:(NSData *)command {
	const unsigned char *bytes = [command bytes];
	unsigned char byte;
	NSColor *color;
	byte = bytes[0];
	if (bytes[0] == (unsigned char)0xff) {
		if (bytes[1] == CMD_SETSTRIPE) {
			NSUInteger stripe = bytes[2];
			if (stripe > 0 && stripe <= NUMBER_OF_LEDS) {
				CGFloat red = bytes[3]/255.0;
				CGFloat green = bytes[4]/255.0;
				CGFloat blue = bytes[5]/255.0;
				if (red == 0 && green == 0 && blue == 0) { // Off pixels look better sort-of transparent
					color = [NSColor colorWithCalibratedRed:LEDBACKGROUNDCOLOR green:LEDBACKGROUNDCOLOR blue:LEDBACKGROUNDCOLOR alpha:1.0];
				}
				else {
					color = [NSColor colorWithCalibratedRed:red green:green blue:blue alpha:1.0];
				}
				[self setStripe:stripe withColor:color];
			}
		}
		else if (bytes[1] == (char)CMD_SETROW) {
			NSColor *color = [NSColor colorWithCalibratedRed:bytes[2]/255.0 green:bytes[3]/255.0 blue:bytes[4]/255.0 alpha:1.0];
			for (int stripe = 1; stripe <= NUMBER_OF_LEDS ; stripe++) {
				[self setStripe:stripe withColor:color];
			}
		}
	}
}

- (void)setStripe:(NSUInteger)stripe withColor:(NSColor *)color {
	NSArray *stripes = [[box contentView] subviews];
	StripeView *stripeView = [stripes objectAtIndex:stripe - 1]; // External adressing ranges from 1 - 32.
	[stripeView setColor:color];
	[stripeView setNeedsDisplay:YES];
}


- (unsigned char)checksum:(unsigned char [])bytes nr_of_bytes:(int)count {
	unsigned char checksum = 0;
	while (count > 0) {
		checksum += bytes[--count];
	}
	return checksum;
}


- (IBAction)buttonOnePressed:(id)sender {
	[self buttonPressed:1];
}
- (IBAction)buttonTwoPressed:(id)sender {
	[self buttonPressed:2];
}
- (void)buttonPressed:(int)button {
	NSLog(@"Button %d pressed.", button);
	unsigned char bytes[7] = {0xff, 0x28, (unsigned char)button, 150, 0x00, 0x00, 0x00};
	bytes[6] = [self checksum:bytes nr_of_bytes:6];
	NSMutableData *clientData = [[NSMutableData alloc] initWithBytes:bytes length:7];
	AsyncSocket *sock = [connectedSockets objectAtIndex:0];
	[sock writeData:clientData withTimeout:-1 tag:BUTTON_PRESSED_TAG];
	[clientData release];
}


- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super dealloc];
}

@end
