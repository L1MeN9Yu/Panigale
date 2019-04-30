//
//  ViewController.m
//  Panigale.Demo.OC
//
//  Created by Mengyu Li on 2019/4/30.
//  Copyright © 2019 L1MeN9Yu. All rights reserved.
//

#import "ViewController.h"
#import "DBManager.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    [[DBManager sharedInstance] setString:@"1" forKey:@"key"];
    NSString *one = [[DBManager sharedInstance] stringForKey:@"key"];
    NSLog(@"value = %@", one);

    [[DBManager sharedInstance] setString:@"2" forKey:@"key"];
    NSString *two = [[DBManager sharedInstance] stringForKey:@"key"];
    NSLog(@"value = %@", two);

    [[DBManager sharedInstance] setString:@"3" forKey:@"key"];
    NSString *three = [[DBManager sharedInstance] stringForKey:@"key"];
    NSLog(@"value = %@", three);
}


@end
