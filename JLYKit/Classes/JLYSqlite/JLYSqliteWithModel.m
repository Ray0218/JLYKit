//
//  JLYSqliteWithModel.m
//  Pods
//
//  Created by 袁宁 on 2017/8/3.
//
//

#import "JLYSqliteWithModel.h"
#import <objc/runtime.h>
#import <objc/message.h>
#ifdef SQLITE_HAS_CODEC
#import "sqlite3.h"
#else
#import <sqlite3.h>
#endif

static const NSString * JLY_String     = @"TEXT";
static const NSString * JLY_Int        = @"INTERGER";
static const NSString * JLY_Boolean    = @"INTERGER";
static const NSString * JLY_Double     = @"DOUBLE";
static const NSString * JLY_Float      = @"DOUBLE";
static const NSString * JLY_Char       = @"NVARCHAR";
static const NSString * JLY_Data       = @"BLOB";
static const NSString * JLY_Array      = @"BLOB";
static const NSString * JLY_Dictionary = @"BLOB";
static const NSString * JLY_Date       = @"DOUBLE";

typedef NS_ENUM(NSInteger, JLYFieldType) {
    JLYFieldTypeString,
    JLYFieldTypeInt,
    JLYFieldTypeBoolean,
    JLYFieldTypeDouble,
    JLYFieldTypeFloat,
    JLYFieldTypeChar,
    JLYFieldTypeNumber,
    JLYFieldTypeData,
    JLYFieldTypeDate,
    JLYFieldTypeArray,
    JLYFieldTypeDictionary
};

typedef NS_ENUM(NSInteger, JLYQueryType) {
    JLYQueryTypeWhere,
    JLYQueryTypeOrder,
    JLYQueryTypeLimit,
    JLYQueryTypeWhereOrder,
    JLYQueryTypeWhereLimit,
    JLYQueryTypeOrderLimit,
    JLYQueryTypeWhereOrderLimit
};

static sqlite3 * _JLY_database;

@interface JLYPropertyInfo : NSObject

@property (nonatomic, assign, readonly) JLYFieldType type;
@property (nonatomic, copy, readonly) NSString * name;
@property (nonatomic, assign, readonly) SEL setter;
@property (nonatomic, assign, readonly) SEL getter;
@end

@implementation JLYPropertyInfo

- (JLYPropertyInfo *)initWithType:(JLYFieldType)type
                      propertyName:(NSString *)property_name
                              name:(NSString *)name {
    self = [super init];
    if (self) {
        _name = name.mutableCopy;
        _type = type;
        _setter = NSSelectorFromString([NSString stringWithFormat:@"set%@%@:",[property_name substringToIndex:1].uppercaseString,[property_name substringFromIndex:1]]);
        _getter = NSSelectorFromString(property_name);
    }
    return self;
}

@end

@interface JLYSqliteWithModel ()

@property (nonatomic, strong) dispatch_semaphore_t dsema;
@property (nonatomic, assign) BOOL check_update;

@end

@implementation JLYSqliteWithModel

- (JLYSqliteWithModel *)init {
    self = [super init];
    if (self) {
        self.dsema = dispatch_semaphore_create(1);
        self.check_update = YES;
    }
    return self;
}

static JLYSqliteWithModel *instance = nil;

+ (JLYSqliteWithModel *)shareInstance{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

+ (JLYSqliteWithModel *)allocWithZone:(struct _NSZone *)zone{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [super allocWithZone:zone];
    });
    return instance;
}

+ (NSString *)databaseCacheDirectory {
    return [NSString stringWithFormat:@"%@/Library/Caches/WHCSqlite/",NSHomeDirectory()];
}

+ (JLYFieldType)parserFieldTypeWithAttr:(NSString *)attr {
    NSArray * sub_attrs = [attr componentsSeparatedByString:@","];
    NSString * first_sub_attr = sub_attrs.firstObject;
    first_sub_attr = [first_sub_attr substringFromIndex:1];
    JLYFieldType field_type = JLYFieldTypeString;
    const char type = *[first_sub_attr UTF8String];
    switch (type) {
        case 'B':
            field_type = JLYFieldTypeBoolean;
            break;
        case 'c':
        case 'C':
            field_type = JLYFieldTypeChar;
            break;
        case 's':
        case 'S':
        case 'i':
        case 'I':
        case 'l':
        case 'L':
        case 'q':
        case 'Q':
            field_type = JLYFieldTypeInt;
            break;
        case 'f':
            field_type = JLYFieldTypeFloat;
            break;
        case 'd':
        case 'D':
            field_type = JLYFieldTypeDouble;
            break;
        default:
            break;
    }
    return field_type;
}

+ (const NSString *)databaseFieldTypeWithType:(JLYFieldType)type {
    switch (type) {
        case JLYFieldTypeString:
            return JLY_String;
        case JLYFieldTypeInt:
            return JLY_Int;
        case JLYFieldTypeNumber:
            return JLY_Double;
        case JLYFieldTypeDouble:
            return JLY_Double;
        case JLYFieldTypeFloat:
            return JLY_Float;
        case JLYFieldTypeChar:
            return JLY_Char;
        case JLYFieldTypeBoolean:
            return JLY_Boolean;
        case JLYFieldTypeData:
            return JLY_Data;
        case JLYFieldTypeDate:
            return JLY_Date;
        case JLYFieldTypeArray:
            return JLY_Array;
        case JLYFieldTypeDictionary:
            return JLY_Dictionary;
        default:
            break;
    }
    return JLY_String;
}

+ (NSDictionary *)parserModelObjectFieldsWithModelClass:(Class)model_class {
    return [self parserSubModelObjectFieldsWithModelClass:model_class propertyName:nil complete:nil];
}

+ (NSDictionary *)parserSubModelObjectFieldsWithModelClass:(Class)model_class propertyName:(NSString *)main_property_name complete:(void(^)(NSString * key, JLYPropertyInfo * property_object))complete {
    BOOL need_dictionary_save = !main_property_name && !complete;
    NSMutableDictionary * fields = need_dictionary_save ? [NSMutableDictionary dictionary] : nil;
    Class super_class = class_getSuperclass(model_class);
    if (super_class != nil &&
        super_class != [NSObject class]) {
        NSDictionary * super_fields = [self parserSubModelObjectFieldsWithModelClass:super_class propertyName:main_property_name complete:complete];
        if (need_dictionary_save) [fields setValuesForKeysWithDictionary:super_fields];
    }
    SEL selector = @selector(jly_IgnorePropertys);
    NSArray * ignore_propertys;
    if ([model_class respondsToSelector:selector]) {
        IMP sqlite_info_func = [model_class methodForSelector:selector];
        NSArray * (*func)(id, SEL) = (void *)sqlite_info_func;
        ignore_propertys = func(model_class, selector);
    }
    unsigned int property_count = 0;
    objc_property_t * propertys = class_copyPropertyList(model_class, &property_count);
    for (int i = 0; i < property_count; i++) {
        objc_property_t property = propertys[i];
        const char * property_name = property_getName(property);
        const char * property_attributes = property_getAttributes(property);
        NSString * property_name_string = [NSString stringWithUTF8String:property_name];
        if (ignore_propertys && [ignore_propertys containsObject:property_name_string]) {
            continue;
        }
        NSString * property_attributes_string = [NSString stringWithUTF8String:property_attributes];
        NSArray * property_attributes_list = [property_attributes_string componentsSeparatedByString:@"\""];
        NSString * name = property_name_string;
        if (![model_class instancesRespondToSelector:NSSelectorFromString([NSString stringWithFormat:@"set%@%@:",[property_name_string substringToIndex:1].uppercaseString,[property_name_string substringFromIndex:1]])]) {
            continue;
        }
        if (!need_dictionary_save) {
            name = [NSString stringWithFormat:@"%@$%@",main_property_name,property_name_string];
        }
        JLYPropertyInfo * property_info = nil;
        if (property_attributes_list.count == 1) {
            // base type
            JLYFieldType type = [self parserFieldTypeWithAttr:property_attributes_list[0]];
            property_info = [[JLYPropertyInfo alloc] initWithType:type propertyName:property_name_string name:name];
        }else {
            // refernece type
            Class class_type = NSClassFromString(property_attributes_list[1]);
            if (class_type == [NSNumber class]) {
                property_info = [[JLYPropertyInfo alloc] initWithType:JLYFieldTypeNumber propertyName:property_name_string name:name];
            }else if (class_type == [NSString class]) {
                property_info = [[JLYPropertyInfo alloc] initWithType:JLYFieldTypeString propertyName:property_name_string name:name];
            }else if (class_type == [NSData class]) {
                property_info = [[JLYPropertyInfo alloc] initWithType:JLYFieldTypeData propertyName:property_name_string name:name];
            }else if (class_type == [NSArray class]) {
                property_info = [[JLYPropertyInfo alloc] initWithType:JLYFieldTypeArray propertyName:property_name_string name:name];
            }else if (class_type == [NSDictionary class]) {
                property_info = [[JLYPropertyInfo alloc] initWithType:JLYFieldTypeDictionary propertyName:property_name_string name:name];
            }else if (class_type == [NSDate class]) {
                property_info = [[JLYPropertyInfo alloc] initWithType:JLYFieldTypeDate propertyName:property_name_string name:name];
            }else if (class_type == [NSSet class] ||
                      class_type == [NSValue class] ||
                      class_type == [NSError class] ||
                      class_type == [NSURL class] ||
                      class_type == [NSStream class] ||
                      class_type == [NSScanner class] ||
                      class_type == [NSException class] ||
                      class_type == [NSBundle class]) {
                [self log:@"检查模型类异常数据类型"];
            }else {
                if (need_dictionary_save) {
                    [self parserSubModelObjectFieldsWithModelClass:class_type propertyName:name complete:^(NSString * key, JLYPropertyInfo *property_object) {
                        [fields setObject:property_object forKey:key];
                    }];
                }else {
                    [self parserSubModelObjectFieldsWithModelClass:class_type propertyName:name complete:complete];
                }
            }
        }
        if (need_dictionary_save && property_info) [fields setObject:property_info forKey:name];
        if (property_info && complete) {
            complete(name,property_info);
        }
    }
    free(propertys);
    return fields;
}

+ (BOOL)isSubModelWithClass:(Class)model_class {
    return (model_class != [NSString class] &&
            model_class != [NSNumber class] &&
            model_class != [NSArray class] &&
            model_class != [NSSet class] &&
            model_class != [NSData class] &&
            model_class != [NSDate class] &&
            model_class != [NSDictionary class] &&
            model_class != [NSValue class] &&
            model_class != [NSError class] &&
            model_class != [NSURL class] &&
            model_class != [NSStream class] &&
            model_class != [NSURLRequest class] &&
            model_class != [NSURLResponse class] &&
            model_class != [NSBundle class] &&
            model_class != [NSScanner class] &&
            model_class != [NSException class]);
}

+ (NSDictionary *)scanCommonSubModel:(id)model isClass:(BOOL)is_class {
    Class model_class = is_class ? model : [model class];
    NSMutableDictionary * sub_model_info = [NSMutableDictionary dictionary];
    Class super_class = class_getSuperclass(model_class);
    if (super_class != nil &&
        super_class != [NSObject class]) {
        [sub_model_info setValuesForKeysWithDictionary:[self scanCommonSubModel:is_class ? super_class : super_class.new isClass:is_class]];
    }
    unsigned int property_count = 0;
    objc_property_t * propertys = class_copyPropertyList(model_class, &property_count);
    for (int i = 0; i < property_count; i++) {
        objc_property_t property = propertys[i];
        const char * property_name = property_getName(property);
        const char * property_attributes = property_getAttributes(property);
        NSString * property_name_string = [NSString stringWithUTF8String:property_name];
        NSString * property_attributes_string = [NSString stringWithUTF8String:property_attributes];
        NSArray * property_attributes_list = [property_attributes_string componentsSeparatedByString:@"\""];
        if (property_attributes_list.count > 1) {
            Class class_type = NSClassFromString(property_attributes_list[1]);
            if ([self isSubModelWithClass:class_type]) {
                if (is_class) {
                    [sub_model_info setObject:property_attributes_list[1] forKey:property_name_string];
                }else {
                    id sub_model = [model valueForKey:property_name_string];
                    if (sub_model) {
                        [sub_model_info setObject:sub_model forKey:property_name_string];
                    }
                }
            }
        }
    }
    free(propertys);
    return sub_model_info;
}

+ (NSDictionary * )scanSubModelClass:(Class)model_class {
    return [self scanCommonSubModel:model_class isClass:YES];
}

+ (NSDictionary * )scanSubModelObject:(NSObject *)model_object {
    return [self scanCommonSubModel:model_object isClass:NO];
}

+ (sqlite_int64)getModelMaxIdWithClass:(Class)model_class {
    sqlite_int64 max_id = 0;
    if (_JLY_database) {
        NSString * select_sql = [NSString stringWithFormat:@"SELECT MAX(%@) AS MAXVALUE FROM %@",[self getMainKeyWithClass:model_class],NSStringFromClass(model_class)];
        sqlite3_stmt * pp_stmt = nil;
        if (sqlite3_prepare_v2(_JLY_database, [select_sql UTF8String], -1, &pp_stmt, nil) == SQLITE_OK) {
            while (sqlite3_step(pp_stmt) == SQLITE_ROW) {
                max_id = sqlite3_column_int64(pp_stmt, 0);
            }
        }
        sqlite3_finalize(pp_stmt);
    }
    return max_id;
}

+ (NSArray *)getModelFieldNameWithClass:(Class)model_class {
    NSMutableArray * field_name_array = [NSMutableArray array];
    if (_JLY_database) {
        NSString *sql = [NSString stringWithFormat:@"pragma table_info ('%@')",NSStringFromClass(model_class)];
        sqlite3_stmt *pp_stmt;
        if(sqlite3_prepare_v2(_JLY_database, [sql UTF8String], -1, &pp_stmt, NULL) == SQLITE_OK){
            while(sqlite3_step(pp_stmt) == SQLITE_ROW) {
                int cols = sqlite3_column_count(pp_stmt);
                if (cols > 1) {
                    NSString *name = [NSString stringWithCString:(const char *)sqlite3_column_text(pp_stmt, 1) encoding:NSUTF8StringEncoding];
                    [field_name_array addObject:name];
                }
            }
            sqlite3_finalize(pp_stmt);
        }
    }
    return field_name_array;
}

+ (void)updateTableFieldWithModel:(Class)model_class
                       newVersion:(NSString *)newVersion
                   localModelName:(NSString *)local_model_name {
    @autoreleasepool {
        NSString * table_name = NSStringFromClass(model_class);
        NSString * cache_directory = [self databaseCacheDirectory];
        NSString * database_cache_path = [NSString stringWithFormat:@"%@%@",cache_directory,local_model_name];
        if (sqlite3_open([database_cache_path UTF8String], &_JLY_database) == SQLITE_OK) {
            NSString * psw_key = [self exceSelector:@selector(jly_SqlitePasswordKey) modelClass:model_class];
            if (psw_key && psw_key.length > 0) {
                if (![self setKey:psw_key]) {
                    [self log:@"给数据库加密失败, 请引入SQLCipher库并配置SQLITE_HAS_CODEC或者pod 'JLYSqliteWithModelKit/SQLCipher'"];
                }
            }
            NSArray * old_model_field_name_array = [self getModelFieldNameWithClass:model_class];
            NSDictionary * new_model_info = [self parserModelObjectFieldsWithModelClass:model_class];
            NSMutableString * delete_field_names = [NSMutableString string];
            NSMutableString * add_field_names = [NSMutableString string];
            [old_model_field_name_array enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                if (new_model_info[obj] == nil) {
                    [delete_field_names appendString:obj];
                    [delete_field_names appendString:@","];
                }
            }];
            [new_model_info enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, JLYPropertyInfo * obj, BOOL * _Nonnull stop) {
                if (![old_model_field_name_array containsObject:key]) {
                    [add_field_names appendFormat:@"%@ %@,",key,[self databaseFieldTypeWithType:obj.type]];
                }
            }];
            if (add_field_names.length > 0) {
                NSArray * add_field_name_array = [add_field_names componentsSeparatedByString:@","];
                [add_field_name_array enumerateObjectsUsingBlock:^(NSString * obj, NSUInteger idx, BOOL * _Nonnull stop) {
                    if (obj.length > 0) {
                        NSString * add_field_name_sql = [NSString stringWithFormat:@"ALTER TABLE %@ ADD %@",table_name,obj];
                        [self execSql:add_field_name_sql];
                    }
                }];
            }
            if (delete_field_names.length > 0) {
                [delete_field_names deleteCharactersInRange:NSMakeRange(delete_field_names.length - 1, 1)];
                NSString * default_key = [self getMainKeyWithClass:model_class];
                if (![default_key isEqualToString:delete_field_names]) {
                    [self shareInstance].check_update = NO;
                    NSArray * old_model_data_array = [self commonQuery:model_class conditions:@[@""] queryType:JLYQueryTypeWhere];
                    [self close];
                    NSFileManager * file_manager = [NSFileManager defaultManager];
                    NSString * file_path = [self localPathWithModel:model_class];
                    if (file_path) {
                        [file_manager removeItemAtPath:file_path error:nil];
                    }
                    
                    if ([self openTable:model_class]) {
                        [self execSql:@"BEGIN TRANSACTION"];
                        [old_model_data_array enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                            [self commonInsert:obj];
                        }];
                        [self execSql:@"COMMIT"];
                        [self close];
                        return;
                    }
                }
            }
            [self close];
            NSString * new_database_cache_path = [NSString stringWithFormat:@"%@%@_v%@.sqlite",cache_directory,table_name,newVersion];
            NSFileManager * file_manager = [NSFileManager defaultManager];
            [file_manager moveItemAtPath:database_cache_path toPath:new_database_cache_path error:nil];
        }
    }
}


+ (BOOL)setKey:(NSString*)key {
    NSData *keyData = [NSData dataWithBytes:[key UTF8String] length:(NSUInteger)strlen([key UTF8String])];
    
    return [self setKeyWithData:keyData];
}

+ (BOOL)setKeyWithData:(NSData *)keyData {
#ifdef SQLITE_HAS_CODEC
    if (!keyData) {
        return NO;
    }
    
    int rc = sqlite3_key(_JLY_database, [keyData bytes], (int)[keyData length]);
    
    return (rc == SQLITE_OK);
#else
    return NO;
#endif
}

+ (NSString *)exceSelector:(SEL)selector modelClass:(Class)model_class {
    if ([model_class respondsToSelector:selector]) {
        IMP sqlite_info_func = [model_class methodForSelector:selector];
        NSString * (*func)(id, SEL) = (void *)sqlite_info_func;
        return func(model_class, selector);
    }
    return nil;
}

+ (NSString *)getMainKeyWithClass:(Class)model_class {
    NSString * main_key = [self exceSelector:@selector(jly_SqliteMainkey) modelClass:model_class];
    if (!main_key || main_key.length == 0) {
        main_key = @"_id";
    }
    return main_key;
}

+ (BOOL)openTable:(Class)model_class {
    NSFileManager * file_manager = [NSFileManager defaultManager];
    NSString * cache_directory = [self databaseCacheDirectory];
    BOOL is_directory = YES;
    if (![file_manager fileExistsAtPath:cache_directory isDirectory:&is_directory]) {
        [file_manager createDirectoryAtPath:cache_directory withIntermediateDirectories:YES attributes:nil error:nil];
    }
    SEL VERSION = @selector(jly_SqliteVersion);
    NSString * version = @"1.0";
    if ([model_class respondsToSelector:VERSION]) {
        version = [self exceSelector:VERSION modelClass:model_class];
        if (!version || version.length == 0) {version = @"1.0";}
        if ([self shareInstance].check_update) {
            NSString * local_model_name = [self localNameWithModel:model_class];
            if (local_model_name != nil &&
                [local_model_name rangeOfString:version].location == NSNotFound) {
                [self updateTableFieldWithModel:model_class
                                     newVersion:version
                                 localModelName:local_model_name];
            }
        }
        [self shareInstance].check_update = YES;
    }
    NSString * database_cache_path = [NSString stringWithFormat:@"%@%@_v%@.sqlite",cache_directory,NSStringFromClass(model_class),version];
    if (sqlite3_open([database_cache_path UTF8String], &_JLY_database) == SQLITE_OK) {
        NSString * psw_key = [self exceSelector:@selector(jly_SqlitePasswordKey) modelClass:model_class];
        if (psw_key && psw_key.length > 0) {
            if (![self setKey:psw_key]) {
                [self log:@"给数据库加密失败, 请引入SQLCipher库并配置SQLITE_HAS_CODEC或者pod 'JLYSqliteWithModelKit/SQLCipher'"];
            }
        }
        return [self createTable:model_class];
    }
    return NO;
}

+ (BOOL)createTable:(Class)model_class {
    NSString * table_name = NSStringFromClass(model_class);
    NSDictionary * field_dictionary = [self parserModelObjectFieldsWithModelClass:model_class];
    if (field_dictionary.count > 0) {
        NSString * main_key = [self getMainKeyWithClass:model_class];
        __block NSString * create_table_sql = [NSString stringWithFormat:@"CREATE TABLE IF NOT EXISTS %@ (%@ INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,",table_name,main_key];
        [field_dictionary enumerateKeysAndObjectsUsingBlock:^(NSString * field, JLYPropertyInfo * property_info, BOOL * _Nonnull stop) {
            create_table_sql = [create_table_sql stringByAppendingFormat:@"%@ %@ DEFAULT ",field, [self databaseFieldTypeWithType:property_info.type]];
            switch (property_info.type) {
                case JLYFieldTypeData:
                case JLYFieldTypeString:
                case JLYFieldTypeChar:
                case JLYFieldTypeDictionary:
                case JLYFieldTypeArray:
                    create_table_sql = [create_table_sql stringByAppendingString:@"NULL,"];
                    break;
                case JLYFieldTypeBoolean:
                case JLYFieldTypeInt:
                    create_table_sql = [create_table_sql stringByAppendingString:@"0,"];
                    break;
                case JLYFieldTypeFloat:
                case JLYFieldTypeDouble:
                case JLYFieldTypeNumber:
                case JLYFieldTypeDate:
                    create_table_sql = [create_table_sql stringByAppendingString:@"0.0,"];
                    break;
                default:
                    break;
            }
        }];
        create_table_sql = [create_table_sql substringWithRange:NSMakeRange(0, create_table_sql.length - 1)];
        create_table_sql = [create_table_sql stringByAppendingString:@")"];
        return [self execSql:create_table_sql];
    }
    return NO;
}

+ (BOOL)execSql:(NSString *)sql {
    BOOL result = sqlite3_exec(_JLY_database, [sql UTF8String], nil, nil, nil) == SQLITE_OK;
    if (!result) {
        [self log:[NSString stringWithFormat:@"执行失败->%@", sql]];
    }
    return result;
}

+ (BOOL)commonInsert:(id)model_object {
    sqlite3_stmt * pp_stmt = nil;
    NSDictionary * field_dictionary = [self parserModelObjectFieldsWithModelClass:[model_object class]];
    NSString * table_name = NSStringFromClass([model_object class]);
    __block NSString * insert_sql = [NSString stringWithFormat:@"INSERT INTO %@ (",table_name];
    NSArray * field_array = field_dictionary.allKeys;
    NSMutableArray * value_array = [NSMutableArray array];
    NSMutableArray * insert_field_array = [NSMutableArray array];
    [field_array enumerateObjectsUsingBlock:^(NSString * field, NSUInteger idx, BOOL * _Nonnull stop) {
        JLYPropertyInfo * property_info = field_dictionary[field];
        [insert_field_array addObject:field];
        insert_sql = [insert_sql stringByAppendingFormat:@"%@,",field];
        id value = nil;
        if ([field rangeOfString:@"$"].location == NSNotFound) {
            value = [model_object valueForKey:field];
        }else {
            value = [model_object valueForKeyPath:[field stringByReplacingOccurrencesOfString:@"$" withString:@"."]];
        }
        if (value) {
            [value_array addObject:value];
        }else {
            switch (property_info.type) {
                case JLYFieldTypeArray: {
                    NSData * array_value = [NSKeyedArchiver archivedDataWithRootObject:[NSArray array]];
                    [value_array addObject:array_value];
                }
                    break;
                case JLYFieldTypeDictionary: {
                    NSData * dictionary_value = [NSKeyedArchiver archivedDataWithRootObject:[NSDictionary dictionary]];
                    [value_array addObject:dictionary_value];
                }
                    break;
                case JLYFieldTypeData: {
                    [value_array addObject:[NSData data]];
                }
                    break;
                case JLYFieldTypeString: {
                    [value_array addObject:@""];
                }
                    break;
                case JLYFieldTypeDate:
                case JLYFieldTypeNumber: {
                    [value_array addObject:@(0.0f)];
                }
                    break;
                case JLYFieldTypeInt: {
                    NSNumber * value = @(((int64_t (*)(id, SEL))(void *) objc_msgSend)((id)model_object, property_info.getter));
                    [value_array addObject:value];
                }
                    break;
                case JLYFieldTypeBoolean: {
                    NSNumber * value = @(((Boolean (*)(id, SEL))(void *) objc_msgSend)((id)model_object, property_info.getter));
                    [value_array addObject:value];
                }
                    break;
                case JLYFieldTypeChar: {
                    NSNumber * value = @(((int8_t (*)(id, SEL))(void *) objc_msgSend)((id)model_object, property_info.getter));
                    [value_array addObject:value];
                }
                    break;
                case JLYFieldTypeDouble: {
                    NSNumber * value = @(((double (*)(id, SEL))(void *) objc_msgSend)((id)model_object, property_info.getter));
                    [value_array addObject:value];
                }
                    break;
                case JLYFieldTypeFloat: {
                    NSNumber * value = @(((float (*)(id, SEL))(void *) objc_msgSend)((id)model_object, property_info.getter));
                    [value_array addObject:value];
                }
                    break;
                default:
                    break;
            }
        }
    }];
    
    insert_sql = [insert_sql substringWithRange:NSMakeRange(0, insert_sql.length - 1)];
    insert_sql = [insert_sql stringByAppendingString:@") VALUES ("];
    
    [field_array enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        insert_sql = [insert_sql stringByAppendingString:@"?,"];
    }];
    insert_sql = [insert_sql substringWithRange:NSMakeRange(0, insert_sql.length - 1)];
    insert_sql = [insert_sql stringByAppendingString:@")"];
    
    if (sqlite3_prepare_v2(_JLY_database, [insert_sql UTF8String], -1, &pp_stmt, nil) == SQLITE_OK) {
        [field_array enumerateObjectsUsingBlock:^(NSString *  _Nonnull field, NSUInteger idx, BOOL * _Nonnull stop) {
            JLYPropertyInfo * property_info = field_dictionary[field];
            id value = value_array[idx];
            int index = (int)[insert_field_array indexOfObject:field] + 1;
            switch (property_info.type) {
                case JLYFieldTypeDictionary:
                case JLYFieldTypeArray: {
                    @try {
                        if ([value isKindOfClass:[NSArray class]] ||
                            [value isKindOfClass:[NSDictionary class]]) {
                            NSData * data = [NSKeyedArchiver archivedDataWithRootObject:value];
                            sqlite3_bind_blob(pp_stmt, index, [data bytes], (int)[data length], SQLITE_TRANSIENT);
                        }else {
                            sqlite3_bind_blob(pp_stmt, index, [value bytes], (int)[value length], SQLITE_TRANSIENT);
                        }
                    } @catch (NSException *exception) {
                        [self log:[NSString stringWithFormat:@"insert 异常 Array/Dictionary类型元素未实现NSCoding协议归档失败"]];
                    }
                }
                    break;
                case JLYFieldTypeData:
                    sqlite3_bind_blob(pp_stmt, index, [value bytes], (int)[value length], SQLITE_TRANSIENT);
                    break;
                case JLYFieldTypeString:
                    if ([value respondsToSelector:@selector(UTF8String)]) {
                        sqlite3_bind_text(pp_stmt, index, [value UTF8String], -1, SQLITE_TRANSIENT);
                    }else {
                        sqlite3_bind_text(pp_stmt, index, [[NSString stringWithFormat:@"%@",value] UTF8String], -1, SQLITE_TRANSIENT);
                    }
                    break;
                case JLYFieldTypeNumber:
                    sqlite3_bind_double(pp_stmt, index, [value doubleValue]);
                    break;
                case JLYFieldTypeInt:
                    sqlite3_bind_int64(pp_stmt, index, (sqlite3_int64)[value longLongValue]);
                    break;
                case JLYFieldTypeBoolean:
                    sqlite3_bind_int(pp_stmt, index, [value boolValue]);
                    break;
                case JLYFieldTypeChar:
                    sqlite3_bind_int(pp_stmt, index, [value intValue]);
                    break;
                case JLYFieldTypeFloat:
                    sqlite3_bind_double(pp_stmt, index, [value floatValue]);
                    break;
                case JLYFieldTypeDouble:
                    sqlite3_bind_double(pp_stmt, index, [value doubleValue]);
                    break;
                case JLYFieldTypeDate: {
                    if ([value isKindOfClass:[NSDate class]]) {
                        sqlite3_bind_double(pp_stmt, index, [(NSDate *)value timeIntervalSince1970]);
                    }else {
                        sqlite3_bind_double(pp_stmt, index, [value doubleValue]);
                    }
                }
                    break;
                default:
                    break;
            }
        }];
        sqlite3_step(pp_stmt);
        sqlite3_finalize(pp_stmt);
    }else {
        [self log:@"Sorry存储数据失败,建议检查模型类属性类型是否符合规范"];
        return NO;
    }
    return YES;
}

+ (BOOL)inserts:(NSArray *)model_array {
    __block BOOL result = YES;
    dispatch_semaphore_wait([self shareInstance].dsema, DISPATCH_TIME_FOREVER);
    @autoreleasepool {
        if (model_array != nil && model_array.count > 0) {
            if ([self openTable:[model_array.firstObject class]]) {
                [self execSql:@"BEGIN TRANSACTION"];
                [model_array enumerateObjectsUsingBlock:^(id model, NSUInteger idx, BOOL * _Nonnull stop) {
                    result = [self commonInsert:model];
                    if (!result) {*stop = YES;}
                }];
                [self execSql:@"COMMIT"];
                [self close];
            }
        }
    }
    dispatch_semaphore_signal([self shareInstance].dsema);
    return result;
}


+ (BOOL)insert:(id)model_object {
    if (model_object) {
        return [self inserts:@[model_object]];
    }
    return NO;
}

+ (id)autoNewSubmodelWithClass:(Class)model_class {
    if (model_class) {
        id model = model_class.new;
        unsigned int property_count = 0;
        objc_property_t * propertys = class_copyPropertyList(model_class, &property_count);
        for (int i = 0; i < property_count; i++) {
            objc_property_t property = propertys[i];
            const char * property_attributes = property_getAttributes(property);
            NSString * property_attributes_string = [NSString stringWithUTF8String:property_attributes];
            NSArray * property_attributes_list = [property_attributes_string componentsSeparatedByString:@"\""];
            if (property_attributes_list.count > 1) {
                // refernece type
                Class class_type = NSClassFromString(property_attributes_list[1]);
                if ([self isSubModelWithClass:class_type]) {
                    const char * property_name = property_getName(property);
                    NSString * property_name_string = [NSString stringWithUTF8String:property_name];
                    [model setValue:[self autoNewSubmodelWithClass:class_type] forKey:property_name_string];
                }
            }
        }
        return model;
    }
    return nil;
}

+ (BOOL)isNumber:(NSString *)cahr {
    int value;
    NSScanner *scan = [NSScanner scannerWithString:cahr];
    return [scan scanInt:&value] && [scan isAtEnd];
}

+ (NSString *)handleWhere:(NSString *)where {
    NSString * where_string = @"";
    if (where && where.length > 0) {
        NSArray * where_list = [where componentsSeparatedByString:@" "];
        NSMutableString * handle_where = [NSMutableString string];
        [where_list enumerateObjectsUsingBlock:^(NSString * sub_where, NSUInteger idx, BOOL * _Nonnull stop) {
            NSRange dot_range = [sub_where rangeOfString:@"."];
            if (dot_range.location != NSNotFound &&
                ![sub_where hasPrefix:@"'"] &&
                ![sub_where hasSuffix:@"'"]) {
                
                __block BOOL has_number = NO;
                NSArray * dot_sub_list = [sub_where componentsSeparatedByString:@"."];
                [dot_sub_list enumerateObjectsUsingBlock:^(NSString * dot_string, NSUInteger idx, BOOL * _Nonnull stop) {
                    NSString * before_char = nil;
                    if (dot_string.length > 0) {
                        before_char = [dot_string substringToIndex:1];
                        if ([self isNumber:before_char]) {
                            has_number = YES;
                            *stop = YES;
                        }
                    }
                }];
                if (!has_number) {
                    [handle_where appendFormat:@"%@ ",[sub_where stringByReplacingOccurrencesOfString:@"." withString:@"$"]];
                }else {
                    [handle_where appendFormat:@"%@ ",sub_where];
                }
            }else {
                [handle_where appendFormat:@"%@ ",sub_where];
            }
        }];
        if ([handle_where hasSuffix:@" "]) {
            [handle_where deleteCharactersInRange:NSMakeRange(handle_where.length - 1, 1)];
        }
        return handle_where;
    }
    return where_string;
}

+ (NSArray *)commonQuery:(Class)model_class conditions:(NSArray *)conditions queryType:(JLYQueryType)query_type {
    NSString * table_name = NSStringFromClass(model_class);
    NSString * select_sql = [NSString stringWithFormat:@"SELECT * FROM %@",table_name];
    NSString * where = nil;
    NSString * order = nil;
    NSString * limit = nil;
    if (conditions != nil && conditions.count > 0) {
        switch (query_type) {
            case JLYQueryTypeWhere: {
                where = [self handleWhere:conditions.firstObject];
                if (where.length > 0) {
                    select_sql = [select_sql stringByAppendingFormat:@" WHERE %@",where];
                }
            }
                break;
            case JLYQueryTypeOrder: {
                order = [conditions.firstObject stringByReplacingOccurrencesOfString:@"." withString:@"$"];
                if (order.length > 0) {
                    select_sql = [select_sql stringByAppendingFormat:@" ORDER %@",order];
                }
            }
                break;
            case JLYQueryTypeLimit:
                limit = [conditions.firstObject stringByReplacingOccurrencesOfString:@"." withString:@"$"];
                if (limit.length > 0) {
                    select_sql = [select_sql stringByAppendingFormat:@" LIMIT %@",limit];
                }
                break;
            case JLYQueryTypeWhereOrder: {
                if (conditions.count > 0) {
                    where = [self handleWhere:conditions.firstObject];
                    if (where.length > 0) {
                        select_sql = [select_sql stringByAppendingFormat:@" WHERE %@",where];
                    }
                }
                if (conditions.count > 1) {
                    order = [conditions.lastObject stringByReplacingOccurrencesOfString:@"." withString:@"$"];
                    if (order.length > 0) {
                        select_sql = [select_sql stringByAppendingFormat:@" ORDER %@",order];
                    }
                }
            }
                break;
            case JLYQueryTypeWhereLimit: {
                if (conditions.count > 0) {
                    where = [self handleWhere:conditions.firstObject];
                    if (where.length > 0) {
                        select_sql = [select_sql stringByAppendingFormat:@" WHERE %@",where];
                    }
                }
                if (conditions.count > 1) {
                    limit = [conditions.lastObject stringByReplacingOccurrencesOfString:@"." withString:@"$"];
                    if (limit.length > 0) {
                        select_sql = [select_sql stringByAppendingFormat:@" LIMIT %@",limit];
                    }
                }
            }
                break;
            case JLYQueryTypeOrderLimit: {
                if (conditions.count > 0) {
                    order = [conditions.firstObject stringByReplacingOccurrencesOfString:@"." withString:@"$"];
                    if (order.length > 0) {
                        select_sql = [select_sql stringByAppendingFormat:@" ORDER %@",order];
                    }
                }
                if (conditions.count > 1) {
                    limit = [conditions.lastObject stringByReplacingOccurrencesOfString:@"." withString:@"$"];
                    if (limit.length > 0) {
                        select_sql = [select_sql stringByAppendingFormat:@" LIMIT %@",limit];
                    }
                }
            }
                break;
            case JLYQueryTypeWhereOrderLimit: {
                if (conditions.count > 0) {
                    where = [self handleWhere:conditions.firstObject];
                    if (where.length > 0) {
                        select_sql = [select_sql stringByAppendingFormat:@" WHERE %@",where];
                    }
                }
                if (conditions.count > 1) {
                    order = [conditions[1] stringByReplacingOccurrencesOfString:@"." withString:@"$"];
                    if (order.length > 0) {
                        select_sql = [select_sql stringByAppendingFormat:@" ORDER %@",order];
                    }
                }
                if (conditions.count > 2) {
                    limit = [conditions.lastObject stringByReplacingOccurrencesOfString:@"." withString:@"$"];
                    if (limit.length > 0) {
                        select_sql = [select_sql stringByAppendingFormat:@" LIMIT %@",limit];
                    }
                }
            }
                break;
            default:
                break;
        }
    }
    return [self startSqlQuery:model_class sql:select_sql];
}

+ (NSArray *)startSqlQuery:(Class)model_class sql:(NSString *)sql {
    NSDictionary * field_dictionary = [self parserModelObjectFieldsWithModelClass:model_class];
    NSMutableArray * model_object_array = [NSMutableArray array];
    sqlite3_stmt * pp_stmt = nil;
    if (sqlite3_prepare_v2(_JLY_database, [sql UTF8String], -1, &pp_stmt, nil) == SQLITE_OK) {
        int colum_count = sqlite3_column_count(pp_stmt);
        while (sqlite3_step(pp_stmt) == SQLITE_ROW) {
            id model_object = [self autoNewSubmodelWithClass:model_class];
            if (!model_object) {break;}
            for (int column = 1; column < colum_count; column++) {
                NSString * field_name = [NSString stringWithCString:sqlite3_column_name(pp_stmt, column) encoding:NSUTF8StringEncoding];
                JLYPropertyInfo * property_info = field_dictionary[field_name];
                if (property_info == nil) continue;
                id current_model_object = model_object;
                if ([field_name rangeOfString:@"$"].location != NSNotFound) {
                    NSString * handle_field_name = [field_name stringByReplacingOccurrencesOfString:@"$" withString:@"."];
                    NSRange backwards_range = [handle_field_name rangeOfString:@"." options:NSBackwardsSearch];
                    NSString * key_path = [handle_field_name substringWithRange:NSMakeRange(0, backwards_range.location)];
                    current_model_object = [model_object valueForKeyPath:key_path];
                    field_name = [handle_field_name substringFromIndex:backwards_range.length + backwards_range.location];
                    if (!current_model_object) continue;
                }
                switch (property_info.type) {
                    case JLYFieldTypeDictionary:
                    case JLYFieldTypeArray: {
                        int length = sqlite3_column_bytes(pp_stmt, column);
                        const void * blob = sqlite3_column_blob(pp_stmt, column);
                        if (blob != NULL) {
                            NSData * value = [NSData dataWithBytes:blob length:length];
                            @try {
                                id set_value = [NSKeyedUnarchiver unarchiveObjectWithData:value];
                                if (set_value) {
                                    [current_model_object setValue:set_value forKey:field_name];
                                }
                            } @catch (NSException *exception) {
                                [self log:@"query 查询异常 Array/Dictionary 元素没实现NSCoding协议解归档失败"];
                            }
                        }
                    }
                        break;
                    case JLYFieldTypeDate: {
                        double value = sqlite3_column_double(pp_stmt, column);
                        if (value > 0) {
                            NSDate * date_value = [NSDate dateWithTimeIntervalSince1970:value];
                            if (date_value) {
                                [current_model_object setValue:date_value forKey:field_name];
                            }
                        }
                    }
                        break;
                    case JLYFieldTypeData: {
                        int length = sqlite3_column_bytes(pp_stmt, column);
                        const void * blob = sqlite3_column_blob(pp_stmt, column);
                        if (blob != NULL) {
                            NSData * value = [NSData dataWithBytes:blob length:length];
                            [current_model_object setValue:value forKey:field_name];
                        }
                    }
                        break;
                    case JLYFieldTypeString: {
                        const unsigned char * text = sqlite3_column_text(pp_stmt, column);
                        if (text != NULL) {
                            NSString * value = [NSString stringWithCString:(const char *)text encoding:NSUTF8StringEncoding];
                            [current_model_object setValue:value forKey:field_name];
                        }
                    }
                        break;
                    case JLYFieldTypeNumber: {
                        double value = sqlite3_column_double(pp_stmt, column);
                        [current_model_object setValue:@(value) forKey:field_name];
                    }
                        break;
                    case JLYFieldTypeInt: {
                        sqlite3_int64 value = sqlite3_column_int64(pp_stmt, column);
                        ((void (*)(id, SEL, int64_t))(void *) objc_msgSend)((id)current_model_object, property_info.setter, value);
                    }
                        break;
                    case JLYFieldTypeFloat: {
                        double value = sqlite3_column_double(pp_stmt, column);
                        ((void (*)(id, SEL, float))(void *) objc_msgSend)((id)current_model_object, property_info.setter, value);
                    }
                        break;
                    case JLYFieldTypeDouble: {
                        double value = sqlite3_column_double(pp_stmt, column);
                        ((void (*)(id, SEL, double))(void *) objc_msgSend)((id)current_model_object, property_info.setter, value);
                    }
                        break;
                    case JLYFieldTypeChar: {
                        int value = sqlite3_column_int(pp_stmt, column);
                        ((void (*)(id, SEL, int))(void *) objc_msgSend)((id)current_model_object, property_info.setter, value);
                    }
                        break;
                    case JLYFieldTypeBoolean: {
                        int value = sqlite3_column_int(pp_stmt, column);
                        ((void (*)(id, SEL, int))(void *) objc_msgSend)((id)current_model_object, property_info.setter, value);
                    }
                        break;
                    default:
                        break;
                }
            }
            [model_object_array addObject:model_object];
        }
    }else {
        [self log:@"Sorry查询语句异常,建议检查查询条件Sql语句语法是否正确"];
    }
    sqlite3_finalize(pp_stmt);
    return model_object_array;
}


+ (NSArray *)startQuery:(Class)model_class conditions:(NSArray *)conditions queryType:(JLYQueryType)query_type {
    if (![self openTable:model_class]) return @[];
    NSArray * model_object_array = [self commonQuery:model_class conditions:conditions queryType:query_type];
    [self close];
    return model_object_array;
}

+ (NSArray *)queryModel:(Class)model_class conditions:(NSArray *)conditions queryType:(JLYQueryType)query_type {
    if (![self localNameWithModel:model_class]) {return @[];}
    dispatch_semaphore_wait([self shareInstance].dsema, DISPATCH_TIME_FOREVER);
    NSArray * model_array = [self startQuery:model_class conditions:conditions queryType:query_type];
    dispatch_semaphore_signal([self shareInstance].dsema);
    return model_array;
}

+ (NSArray *)query:(Class)model_class {
    return [self query:model_class where:nil];
}

+ (NSArray *)query:(Class)model_class where:(NSString *)where {
    return [self queryModel:model_class conditions:@[where == nil ? @"" : where] queryType:JLYQueryTypeWhere];
}

+ (NSArray *)query:(Class)model_class order:(NSString *)order {
    return [self queryModel:model_class conditions:@[order == nil ? @"" : order] queryType:JLYQueryTypeOrder];
}


+ (NSArray *)query:(Class)model_class limit:(NSString *)limit {
    return [self queryModel:model_class conditions:@[limit == nil ? @"" : limit] queryType:JLYQueryTypeLimit];
}

+ (NSArray *)query:(Class)model_class where:(NSString *)where order:(NSString *)order {
    return [self queryModel:model_class conditions:@[where == nil ? @"" : where,
                                                     order == nil ? @"" : order] queryType:JLYQueryTypeWhereOrder];
}

+ (NSArray *)query:(Class)model_class where:(NSString *)where limit:(NSString *)limit {
    return [self queryModel:model_class conditions:@[where == nil ? @"" : where,
                                                     limit == nil ? @"" : limit] queryType:JLYQueryTypeWhereLimit];
}

+ (NSArray *)query:(Class)model_class order:(NSString *)order limit:(NSString *)limit {
    return [self queryModel:model_class conditions:@[order == nil ? @"" : order,
                                                     limit == nil ? @"" : limit] queryType:JLYQueryTypeOrderLimit];
}

+ (NSArray *)query:(Class)model_class where:(NSString *)where order:(NSString *)order limit:(NSString *)limit {
    return [self queryModel:model_class conditions:@[where == nil ? @"" : where,
                                                     order == nil ? @"" : order,
                                                     limit == nil ? @"" : limit] queryType:JLYQueryTypeWhereOrderLimit];
}

+ (NSArray *)query:(Class)model_class sql:(NSString *)sql {
    if (sql && sql.length > 0) {
        if (![self localNameWithModel:model_class]) {return @[];}
        dispatch_semaphore_wait([self shareInstance].dsema, DISPATCH_TIME_FOREVER);
        if (![self openTable:model_class]) return @[];
        NSArray * model_object_array = [self startSqlQuery:model_class sql:sql];
        [self close];
        dispatch_semaphore_signal([self shareInstance].dsema);
        return model_object_array;
    }
    [self log:@"sql 查询语句不能为空"];
    return @[];
}

+ (NSUInteger)count:(Class)model_class {
    NSNumber * count = [self query:model_class func:@"count(*)"];
    return count ? count.unsignedIntegerValue : 0;
}

+ (id)query:(Class)model_class func:(NSString *)func {
    return [self query:model_class func:func condition:nil];
}

+ (id)query:(Class)model_class func:(NSString *)func condition:(NSString *)condition {
    if (![self localNameWithModel:model_class]) {return nil;}
    dispatch_semaphore_wait([self shareInstance].dsema, DISPATCH_TIME_FOREVER);
    if (![self openTable:model_class]) return @[];
    NSMutableArray * result_array = [NSMutableArray array];
    @autoreleasepool {
        NSString * table_name = NSStringFromClass(model_class);
        if (func == nil || func.length == 0) {
            [self log:@"发现错误 Sqlite Func 不能为空"];
            return nil;
        }
        if (condition == nil) {
            condition = @"";
        }else {
            condition = [self handleWhere:condition];
        }
        NSString * select_sql = [NSString stringWithFormat:@"SELECT %@ FROM %@ %@",func,table_name,condition];
        sqlite3_stmt * pp_stmt = nil;
        if (sqlite3_prepare_v2(_JLY_database, [select_sql UTF8String], -1, &pp_stmt, nil) == SQLITE_OK) {
            int colum_count = sqlite3_column_count(pp_stmt);
            while (sqlite3_step(pp_stmt) == SQLITE_ROW) {
                NSMutableArray * row_result_array = [NSMutableArray array];
                for (int column = 0; column < colum_count; column++) {
                    int column_type = sqlite3_column_type(pp_stmt, column);
                    switch (column_type) {
                        case SQLITE_INTEGER: {
                            sqlite3_int64 value = sqlite3_column_int64(pp_stmt, column);
                            [row_result_array addObject:@(value)];
                        }
                            break;
                        case SQLITE_FLOAT: {
                            double value = sqlite3_column_double(pp_stmt, column);
                            [row_result_array addObject:@(value)];
                        }
                            break;
                        case SQLITE_TEXT: {
                            const unsigned char * text = sqlite3_column_text(pp_stmt, column);
                            if (text != NULL) {
                                NSString * value = [NSString stringWithCString:(const char *)text encoding:NSUTF8StringEncoding];
                                [row_result_array addObject:value];
                            }
                        }
                            break;
                        case SQLITE_BLOB: {
                            int length = sqlite3_column_bytes(pp_stmt, column);
                            const void * blob = sqlite3_column_blob(pp_stmt, column);
                            if (blob != NULL) {
                                NSData * value = [NSData dataWithBytes:blob length:length];
                                [row_result_array addObject:value];
                            }
                        }
                            break;
                        default:
                            break;
                    }
                }
                if (row_result_array.count > 0) {
                    [result_array addObject:row_result_array];
                }
            }
            sqlite3_finalize(pp_stmt);
        }else {
            [self log:@"Sorry 查询失败, 建议检查sqlite 函数书写格式是否正确！"];
        }
        [self close];
        if (result_array.count > 0) {
            NSMutableDictionary * handle_result_dict = [NSMutableDictionary dictionary];
            [result_array enumerateObjectsUsingBlock:^(NSArray * row_result_array, NSUInteger idx, BOOL * _Nonnull stop) {
                [row_result_array enumerateObjectsUsingBlock:^(id _Nonnull column_value, NSUInteger idx, BOOL * _Nonnull stop) {
                    NSString * column_array_key = @(idx).stringValue;
                    NSMutableArray * column_value_array = handle_result_dict[column_array_key];
                    if (!column_value_array) {
                        column_value_array = [NSMutableArray array];
                        handle_result_dict[column_array_key] = column_value_array;
                    }
                    [column_value_array addObject:column_value];
                }];
            }];
            NSArray * all_keys = handle_result_dict.allKeys;
            NSArray * handle_column_array_key = [all_keys sortedArrayUsingComparator:^NSComparisonResult(NSString * key1, NSString * key2) {
                NSComparisonResult result = [key1 compare:key2];
                return result == NSOrderedDescending ? NSOrderedAscending : result;
            }];
            [result_array removeAllObjects];
            if (handle_column_array_key) {
                [handle_column_array_key enumerateObjectsUsingBlock:^(NSString * key, NSUInteger idx, BOOL * _Nonnull stop) {
                    [result_array addObject:handle_result_dict[key]];
                }];
            }
        }
    }
    dispatch_semaphore_signal([self shareInstance].dsema);
    if (result_array.count == 1) {
        NSArray * element = result_array.firstObject;
        if (element.count > 1){
            return element;
        }
        return element.firstObject;
    }else if (result_array.count > 1) {
        return result_array;
    }
    return nil;
}

+ (BOOL)updateModel:(id)model_object where:(NSString *)where {
    if (model_object == nil) return NO;
    Class model_class = [model_object class];
    if (![self openTable:model_class]) return NO;
    sqlite3_stmt * pp_stmt = nil;
    NSDictionary * field_dictionary = [self parserModelObjectFieldsWithModelClass:model_class];
    NSString * table_name = NSStringFromClass(model_class);
    __block NSString * update_sql = [NSString stringWithFormat:@"UPDATE %@ SET ",table_name];
    
    NSArray * field_array = field_dictionary.allKeys;
    NSMutableArray * update_field_array = [NSMutableArray array];
    [field_array enumerateObjectsUsingBlock:^(id  _Nonnull field, NSUInteger idx, BOOL * _Nonnull stop) {
        update_sql = [update_sql stringByAppendingFormat:@"%@ = ?,",field];
        [update_field_array addObject:field];
    }];
    update_sql = [update_sql substringWithRange:NSMakeRange(0, update_sql.length - 1)];
    if (where != nil && where.length > 0) {
        update_sql = [update_sql stringByAppendingFormat:@" WHERE %@", [self handleWhere:where]];
    }
    if (sqlite3_prepare_v2(_JLY_database, [update_sql UTF8String], -1, &pp_stmt, nil) == SQLITE_OK) {
        [field_array enumerateObjectsUsingBlock:^(id  _Nonnull field, NSUInteger idx, BOOL * _Nonnull stop) {
            JLYPropertyInfo * property_info = field_dictionary[field];
            id current_model_object = model_object;
            NSString * actual_field = field;
            if ([field rangeOfString:@"$"].location != NSNotFound) {
                NSString * handle_field_name = [field stringByReplacingOccurrencesOfString:@"$" withString:@"."];
                NSRange backwards_range = [handle_field_name rangeOfString:@"." options:NSBackwardsSearch];
                NSString * key_path = [handle_field_name substringWithRange:NSMakeRange(0, backwards_range.location)];
                current_model_object = [model_object valueForKeyPath:key_path];
                actual_field = [handle_field_name substringFromIndex:backwards_range.location + backwards_range.length];
                if (!current_model_object) {*stop = YES;}
            }
            int index = (int)[update_field_array indexOfObject:field] + 1;
            switch (property_info.type) {
                case JLYFieldTypeDictionary:
                case JLYFieldTypeArray: {
                    id value = [current_model_object valueForKey:actual_field];
                    if (value == nil) {
                        value = property_info.type == JLYFieldTypeDictionary ? [NSDictionary dictionary] : [NSArray array];
                    }
                    @try {
                        NSData * set_value = [NSKeyedArchiver archivedDataWithRootObject:value];
                        sqlite3_bind_blob(pp_stmt, index, [set_value bytes], (int)[set_value length], SQLITE_TRANSIENT);
                    } @catch (NSException *exception) {
                        [self log:@"update 操作异常 Array/Dictionary 元素没实现NSCoding协议归档失败"];
                    }
                }
                    break;
                case JLYFieldTypeDate: {
                    NSDate * value = [current_model_object valueForKey:actual_field];
                    if (value == nil) {
                        sqlite3_bind_double(pp_stmt, index, 0.0);
                    }else {
                        sqlite3_bind_double(pp_stmt, index, [value timeIntervalSince1970]);
                    }
                }
                    break;
                case JLYFieldTypeData: {
                    NSData * value = [current_model_object valueForKey:actual_field];
                    if (value == nil) {
                        value = [NSData data];
                    }
                    sqlite3_bind_blob(pp_stmt, index, [value bytes], (int)[value length], SQLITE_TRANSIENT);
                }
                    break;
                case JLYFieldTypeString: {
                    NSString * value = [current_model_object valueForKey:actual_field];
                    if (value == nil) {
                        value = @"";
                    }
                    if ([value respondsToSelector:@selector(UTF8String)]) {
                        sqlite3_bind_text(pp_stmt, index, [value UTF8String], -1, SQLITE_TRANSIENT);
                    }else {
                        sqlite3_bind_text(pp_stmt, index, [[NSString stringWithFormat:@"%@",value] UTF8String], -1, SQLITE_TRANSIENT);
                    }
                }
                    break;
                case JLYFieldTypeNumber: {
                    NSNumber * value = [current_model_object valueForKey:actual_field];
                    if (value == nil) {
                        value = @(0.0);
                    }
                    sqlite3_bind_double(pp_stmt, index, [value doubleValue]);
                }
                    break;
                case JLYFieldTypeInt: {
                    /* 32bit os type issue
                     long value = ((long (*)(id, SEL))(void *) objc_msgSend)((id)sub_model_object, property_info.getter);*/
                    NSNumber * value = [current_model_object valueForKey:actual_field];
                    sqlite3_bind_int64(pp_stmt, index, (sqlite3_int64)[value longLongValue]);
                }
                    break;
                case JLYFieldTypeChar: {
                    char value = ((char (*)(id, SEL))(void *) objc_msgSend)((id)current_model_object, property_info.getter);
                    sqlite3_bind_int(pp_stmt, index, value);
                }
                    break;
                case JLYFieldTypeFloat: {
                    float value = ((float (*)(id, SEL))(void *) objc_msgSend)((id)current_model_object, property_info.getter);
                    sqlite3_bind_double(pp_stmt, index, value);
                }
                    break;
                case JLYFieldTypeDouble: {
                    double value = ((double (*)(id, SEL))(void *) objc_msgSend)((id)current_model_object, property_info.getter);
                    sqlite3_bind_double(pp_stmt, index, value);
                }
                    break;
                case JLYFieldTypeBoolean: {
                    BOOL value = ((BOOL (*)(id, SEL))(void *) objc_msgSend)((id)current_model_object, property_info.getter);
                    sqlite3_bind_int(pp_stmt, index, value);
                }
                    break;
                default:
                    break;
            }
        }];
        sqlite3_step(pp_stmt);
        sqlite3_finalize(pp_stmt);
    }else {
        [self log:@"更新失败"];
        [self close];
        return NO;
    }
    [self close];
    return YES;
}

+ (BOOL)update:(id)model_object where:(NSString *)where {
    BOOL result = YES;
    if ([self localNameWithModel:[model_object class]]) {
        dispatch_semaphore_wait([self shareInstance].dsema, DISPATCH_TIME_FOREVER);
        @autoreleasepool {
            result = [self updateModel:model_object where:where];
        }
        dispatch_semaphore_signal([self shareInstance].dsema);
    }else {
        result = NO;
    }
    return result;
}

+ (BOOL)update:(Class)model_class value:(NSString *)value where:(NSString *)where {
    if (model_class == nil) return NO;
    BOOL result = YES;
    if ([self localNameWithModel:model_class]) {
        dispatch_semaphore_wait([self shareInstance].dsema, DISPATCH_TIME_FOREVER);
        @autoreleasepool {
            if (value != nil && value.length > 0) {
                if ([self openTable:model_class]) {
                    NSString * table_name = NSStringFromClass(model_class);
                    NSString * update_sql = [NSString stringWithFormat:@"UPDATE %@ SET %@",table_name,value];
                    if (where != nil && where.length > 0) {
                        update_sql = [update_sql stringByAppendingFormat:@" WHERE %@", [self handleWhere:where]];
                    }
                    result = [self execSql:update_sql];
                    [self close];
                }else {
                    result = NO;
                }
            }else {
                result = NO;
            }
        }
        dispatch_semaphore_signal([self shareInstance].dsema);
    }else {
        result = NO;
    }
    return result;
}

+ (BOOL)clear:(Class)model_class {
    return [self delete:model_class where:nil];
}

+ (BOOL)commonDeleteModel:(Class)model_class where:(NSString *)where {
    BOOL result = YES;
    if ([self localNameWithModel:model_class]) {
        if ([self openTable:model_class]) {
            NSString * table_name = NSStringFromClass(model_class);
            NSString * delete_sql = [NSString stringWithFormat:@"DELETE FROM %@",table_name];
            if (where != nil && where.length > 0) {
                delete_sql = [delete_sql stringByAppendingFormat:@" WHERE %@",[self handleWhere:where]];
            }
            result = [self execSql:delete_sql];
            [self close];
        }else {
            result = NO;
        }
    }else {
        result = NO;
    }
    return result;
}

+ (BOOL)delete:(Class)model_class where:(NSString *)where {
    BOOL result = YES;
    dispatch_semaphore_wait([self shareInstance].dsema, DISPATCH_TIME_FOREVER);
    @autoreleasepool {
        result = [self commonDeleteModel:model_class where:where];
    }
    dispatch_semaphore_signal([self shareInstance].dsema);
    return result;
}

+ (void)close {
    if (_JLY_database) {
        sqlite3_close(_JLY_database);
        _JLY_database = nil;
    }
}

+ (void)removeAllModel {
    dispatch_semaphore_wait([self shareInstance].dsema, DISPATCH_TIME_FOREVER);
    @autoreleasepool {
        NSFileManager * file_manager = [NSFileManager defaultManager];
        NSString * cache_path = [self databaseCacheDirectory];
        BOOL is_directory = YES;
        if ([file_manager fileExistsAtPath:cache_path isDirectory:&is_directory]) {
            NSArray * file_array = [file_manager contentsOfDirectoryAtPath:cache_path error:nil];
            [file_array enumerateObjectsUsingBlock:^(id  _Nonnull file, NSUInteger idx, BOOL * _Nonnull stop) {
                if (![file isEqualToString:@".DS_Store"]) {
                    NSString * file_path = [NSString stringWithFormat:@"%@%@",cache_path,file];
                    [file_manager removeItemAtPath:file_path error:nil];
                    [self log:[NSString stringWithFormat:@"已经删除了数据库 ->%@",file_path]];
                }
            }];
        }
    }
    dispatch_semaphore_signal([self shareInstance].dsema);
}

+ (void)removeModel:(Class)model_class {
    dispatch_semaphore_wait([self shareInstance].dsema, DISPATCH_TIME_FOREVER);
    @autoreleasepool {
        NSFileManager * file_manager = [NSFileManager defaultManager];
        NSString * file_path = [self localPathWithModel:model_class];
        if (file_path) {
            [file_manager removeItemAtPath:file_path error:nil];
        }
    }
    dispatch_semaphore_signal([self shareInstance].dsema);
}

+ (NSString *)commonLocalPathWithModel:(Class)model_class isPath:(BOOL)isPath {
    NSString * class_name = NSStringFromClass(model_class);
    NSFileManager * file_manager = [NSFileManager defaultManager];
    NSString * file_directory = [self databaseCacheDirectory];
    BOOL isDirectory = YES;
    __block NSString * file_path = nil;
    if ([file_manager fileExistsAtPath:file_directory isDirectory:&isDirectory]) {
        NSArray <NSString *> * file_name_array = [file_manager contentsOfDirectoryAtPath:file_directory error:nil];
        if (file_name_array != nil && file_name_array.count > 0) {
            [file_name_array enumerateObjectsUsingBlock:^(NSString * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                if ([obj rangeOfString:class_name].location != NSNotFound) {
                    if (isPath) {
                        file_path = [NSString stringWithFormat:@"%@%@",file_directory,obj];
                    }else {
                        file_path = [obj mutableCopy];
                    }
                    *stop = YES;
                }
            }];
        }
    }
    return file_path;
}

+ (NSString *)localNameWithModel:(Class)model_class {
    return [self commonLocalPathWithModel:model_class isPath:NO];
}

+ (NSString *)localPathWithModel:(Class)model_class {
    return [self commonLocalPathWithModel:model_class isPath:YES];
}

+ (NSString *)versionWithModel:(Class)model_class {
    NSString * model_version = nil;
    NSString * model_name = [self localNameWithModel:model_class];
    if (model_name) {
        NSRange end_range = [model_name rangeOfString:@"." options:NSBackwardsSearch];
        NSRange start_range = [model_name rangeOfString:@"v" options:NSBackwardsSearch];
        if (end_range.location != NSNotFound &&
            start_range.location != NSNotFound) {
            model_version = [model_name substringWithRange:NSMakeRange(start_range.length + start_range.location, end_range.location - (start_range.length + start_range.location))];
        }
    }
    return model_version;
}

+ (void)log:(NSString *)msg {
    NSLog(@"JLYSqliteWithModel:[%@]",msg);
}

@end
