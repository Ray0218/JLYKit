//
//  NSObject+DateString.m
//  iOrder2.0
//
//  Created by TJBT on 16/1/6.
//  Copyright © 2016年 TIANJIN BEITA TECHNOLOGY CO.,LTD. All rights reserved.
//

#import "NSObject+DateString.h"

#define CurrentCalender [NSCalendar currentCalendar]

@implementation NSObject (DateString)

- (NSString *)stringFromTime:(long long)time DateFormat:(NSString *)dateFormat{
    return [NSDate jly_stringWithDate:[NSDate dateWithTimeIntervalSince1970:time / 1000] format:dateFormat];
}

- (NSString *)stringFromDate:(NSDate *)date DateFormat:(NSString *)dateFormat{
    return [NSDate jly_stringWithDate:date format:dateFormat];
}

- (NSString *)todayString{
    return [NSDate jly_stringWithDate:[NSDate date] format:[NSDate jly_ymdFormat]];
}

- (NSString *)yesterdayString{
    return [NSDate jly_stringWithDate:[NSDate dateWithTimeIntervalSinceNow:-(24*60*60)] format:[NSDate jly_ymdFormat]];
}

- (NSString *)currentMonthBeginDay{
    return [NSDate jly_stringWithDate:[NSDate jly_begindayOfMonth:[NSDate date]] format:[NSDate jly_ymdFormat]];
}

- (NSString *)currentMonthEndDay{
    return [self monthEndDay:[NSDate date]];
}

- (NSString *)lastMonthBeginDay{
    NSDateComponents *cmp = [CurrentCalender components:(NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay | NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond) fromDate:[NSDate date]];
    [cmp setMonth:[cmp month] - 1];
    return [NSDate jly_stringWithDate:[NSDate jly_begindayOfMonth:[CurrentCalender dateFromComponents:cmp]] format:[NSDate jly_ymdFormat]];
}

- (NSString *)lastMonthEndDay{
    NSDateComponents *cmp = [CurrentCalender components:(NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay | NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond) fromDate:[NSDate date]];
    [cmp setMonth:[cmp month] - 1];
    return [NSDate jly_stringWithDate:[NSDate jly_lastdayOfMonth:[CurrentCalender dateFromComponents:cmp]] format:[NSDate jly_ymdFormat]];
}

- (NSString *)monthBeginDay:(NSDate *)date{
    return [NSDate jly_stringWithDate:[NSDate jly_begindayOfMonth:date] format:[NSDate jly_ymdFormat]];
}

- (NSString *)monthEndDay:(NSDate *)date{
    return [NSDate jly_stringWithDate:[NSDate jly_lastdayOfMonth:date] format:[NSDate jly_ymdFormat]];
}

- (NSString *)calculateFromDate:(long long)time{
    return [NSDate jly_timeInfoWithDate:[NSDate dateWithTimeIntervalSince1970:time / 1000]];
}

- (NSString *)currentMonth{
    return [self stringFromDate:[NSDate date] DateFormat:@"yyyy年MM月"];
}

- (NSDate *)monthEndDate:(NSDate *)date{
    NSCalendar *calendar = [NSCalendar currentCalendar];
    [calendar setFirstWeekday:2];//设定周一为周首日
    double interval = 0;
    NSDate *beginDate = nil;
    NSDate *endDate = nil;
#if __IPHONE_OS_VERSION_MIN_REQUIRED >= __IPHONE_8_0
    // NSDayCalendarUnit
    BOOL ok = [calendar rangeOfUnit:NSCalendarUnitMonth startDate:&beginDate interval:&interval forDate:date];
#else
    BOOL ok = [calendar rangeOfUnit:NSMonthCalendarUnit startDate:&beginDate interval:&interval forDate:date];
#endif
    //分别修改为 NSDayCalendarUnit NSWeekCalendarUnit NSYearCalendarUnit
    if (ok) {
        endDate = [beginDate dateByAddingTimeInterval:interval-1];
    }else {
        return [NSDate date];
    }
    return endDate;
}


@end
