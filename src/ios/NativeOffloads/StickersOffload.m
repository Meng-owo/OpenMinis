//
//  StickersOffload.m
//  MinisApp
//
//  Native offload handler for `minis-stickers`.
//

#import <Foundation/Foundation.h>
#import "NativeOffloadUtils.h"
#include "kernel/native_offload.h"
#include <unistd.h>

#if __has_include("Minis-Swift.h")
#import "Minis-Swift.h"
#else
@interface StickersOffloadBridge : NSObject
+ (NSDictionary * _Nonnull)listStickersWithCategory:(NSString * _Nullable)category limit:(NSInteger)limit;
+ (NSDictionary * _Nonnull)getStickerWithId:(NSString * _Nonnull)id;
+ (NSDictionary * _Nonnull)editStickerWithId:(NSString * _Nonnull)id
                                       title:(NSString * _Nullable)title
                                        desc:(NSString * _Nullable)desc
                                    category:(NSString * _Nullable)category
                                     content:(NSString * _Nullable)content;
+ (NSDictionary * _Nonnull)deleteStickerWithId:(NSString * _Nonnull)id;
+ (NSDictionary * _Nonnull)batchMoveWithIds:(NSArray<NSString *> * _Nonnull)ids category:(NSString * _Nonnull)category;
+ (NSDictionary * _Nonnull)listCategories;
@end
#endif

static NSString *const TOOL_NAME = @"minis-stickers";

static NSString *const HELP_TEXT =
    @"minis-stickers - Manage chat sticker catalog, descriptions and categories\n"
     "\n"
     "USAGE:\n"
     "  minis-stickers <command> [options]\n"
     "\n"
     "COMMANDS:\n"
     "  list         List stickers (filter by --category, limit with --limit)\n"
     "  get          Get details of a sticker (--id <id>)\n"
     "  edit         Edit sticker metadata (--id <id> [--title <title>] [--desc <desc>] [--category <cat>])\n"
     "  delete       Delete a sticker and its disk image file (--id <id>)\n"
     "  batch-move   Batch move stickers to a category (--ids <id1,id2,...> --category <cat>)\n"
     "  categories   List all sticker categories\n"
     "\n"
     "OPTIONS:\n"
     "  --id <id>              Sticker ID (e.g. 001)\n"
     "  --ids <id1,id2,...>    Comma-separated sticker IDs\n"
     "  --category <cat>       Category name (e.g. 开心, 撒娇)\n"
     "  --title <title>        Sticker title\n"
     "  --desc <desc>          Short description (trigger alias for matching)\n"
     "  --content <content>    Sticker description text\n"
     "  --limit <n>            Max results (default: all)\n"
     "  --help, -h             Show this help message\n"
     "  --compact              Minimize JSON output\n"
     "  -q, --quiet            Output only data field\n";

static int cmd_list(int argc, char **argv, int stdout_fd, BOOL compact, BOOL quiet) {
    NSString *category = noff_find_arg(argc, argv, "--category");
    NSString *limitRaw = noff_find_arg(argc, argv, "--limit");
    NSInteger limit = limitRaw ? [limitRaw integerValue] : 0;

    NSDictionary *data = [StickersOffloadBridge listStickersWithCategory:category limit:limit];
    NSDictionary *result = noff_json_envelope(TOOL_NAME, @"list", data);
    noff_emit_json(stdout_fd, result, compact, quiet);
    return NOFF_EXIT_SUCCESS;
}

static int cmd_get(int argc, char **argv, int stdout_fd, int stderr_fd, BOOL compact, BOOL quiet) {
    NSString *idVal = noff_find_arg(argc, argv, "--id");
    if (!idVal || idVal.length == 0) {
        NSDictionary *err = noff_json_error(TOOL_NAME, @"get", NOFF_ERR_INVALID_ARGS, @"--id <id> is required.");
        noff_emit_json(stdout_fd, err, compact, quiet);
        return NOFF_EXIT_INVALID_ARGS;
    }
    NSDictionary *data = [StickersOffloadBridge getStickerWithId:idVal];
    NSDictionary *result = noff_json_envelope(TOOL_NAME, @"get", data);
    noff_emit_json(stdout_fd, result, compact, quiet);
    return NOFF_EXIT_SUCCESS;
}

static int cmd_edit(int argc, char **argv, int stdout_fd, int stderr_fd, BOOL compact, BOOL quiet) {
    NSString *idVal = noff_find_arg(argc, argv, "--id");
    if (!idVal || idVal.length == 0) {
        NSDictionary *err = noff_json_error(TOOL_NAME, @"edit", NOFF_ERR_INVALID_ARGS, @"--id <id> is required.");
        noff_emit_json(stdout_fd, err, compact, quiet);
        return NOFF_EXIT_INVALID_ARGS;
    }
    NSString *title = noff_find_arg(argc, argv, "--title");
    NSString *desc = noff_find_arg(argc, argv, "--desc");
    NSString *cat = noff_find_arg(argc, argv, "--category");
    NSString *content = noff_find_arg(argc, argv, "--content");

    NSDictionary *data = [StickersOffloadBridge editStickerWithId:idVal title:title desc:desc category:cat content:content];
    NSDictionary *result = noff_json_envelope(TOOL_NAME, @"edit", data);
    noff_emit_json(stdout_fd, result, compact, quiet);
    return NOFF_EXIT_SUCCESS;
}

static int cmd_delete(int argc, char **argv, int stdout_fd, int stderr_fd, BOOL compact, BOOL quiet) {
    NSString *idVal = noff_find_arg(argc, argv, "--id");
    if (!idVal || idVal.length == 0) {
        NSDictionary *err = noff_json_error(TOOL_NAME, @"delete", NOFF_ERR_INVALID_ARGS, @"--id <id> is required.");
        noff_emit_json(stdout_fd, err, compact, quiet);
        return NOFF_EXIT_INVALID_ARGS;
    }
    NSDictionary *data = [StickersOffloadBridge deleteStickerWithId:idVal];
    NSDictionary *result = noff_json_envelope(TOOL_NAME, @"delete", data);
    noff_emit_json(stdout_fd, result, compact, quiet);
    return NOFF_EXIT_SUCCESS;
}

static int cmd_batch_move(int argc, char **argv, int stdout_fd, int stderr_fd, BOOL compact, BOOL quiet) {
    NSString *rawIds = noff_find_arg(argc, argv, "--ids");
    NSString *cat = noff_find_arg(argc, argv, "--category");
    if (!rawIds || rawIds.length == 0 || !cat || cat.length == 0) {
        NSDictionary *err = noff_json_error(TOOL_NAME, @"batch-move", NOFF_ERR_INVALID_ARGS, @"--ids <id1,id2> and --category <cat> are required.");
        noff_emit_json(stdout_fd, err, compact, quiet);
        return NOFF_EXIT_INVALID_ARGS;
    }
    NSArray *ids = [rawIds componentsSeparatedByString:@","];
    NSDictionary *data = [StickersOffloadBridge batchMoveWithIds:ids category:cat];
    NSDictionary *result = noff_json_envelope(TOOL_NAME, @"batch-move", data);
    noff_emit_json(stdout_fd, result, compact, quiet);
    return NOFF_EXIT_SUCCESS;
}

static int cmd_categories(int argc, char **argv, int stdout_fd, BOOL compact, BOOL quiet) {
    NSDictionary *data = [StickersOffloadBridge listCategories];
    NSDictionary *result = noff_json_envelope(TOOL_NAME, @"categories", data);
    noff_emit_json(stdout_fd, result, compact, quiet);
    return NOFF_EXIT_SUCCESS;
}

static int stickers_handler(int argc, char **argv, int stdin_fd, int stdout_fd, int stderr_fd) {
    if (noff_has_flag(argc, argv, "--help") || noff_has_flag(argc, argv, "-h")) {
        noff_emit_help(stderr_fd, HELP_TEXT);
        return NOFF_EXIT_SUCCESS;
    }

    BOOL compact = noff_has_flag(argc, argv, "--compact");
    BOOL quiet = noff_has_flag(argc, argv, "-q") || noff_has_flag(argc, argv, "--quiet");

    NSString *subcmd = noff_get_subcommand(argc, argv);
    if (!subcmd || [subcmd isEqualToString:@"list"]) {
        return cmd_list(argc, argv, stdout_fd, compact, quiet);
    } else if ([subcmd isEqualToString:@"get"]) {
        return cmd_get(argc, argv, stdout_fd, stderr_fd, compact, quiet);
    } else if ([subcmd isEqualToString:@"edit"]) {
        return cmd_edit(argc, argv, stdout_fd, stderr_fd, compact, quiet);
    } else if ([subcmd isEqualToString:@"delete"]) {
        return cmd_delete(argc, argv, stdout_fd, stderr_fd, compact, quiet);
    } else if ([subcmd isEqualToString:@"batch-move"]) {
        return cmd_batch_move(argc, argv, stdout_fd, stderr_fd, compact, quiet);
    } else if ([subcmd isEqualToString:@"categories"]) {
        return cmd_categories(argc, argv, stdout_fd, compact, quiet);
    }

    noff_emit_help(stderr_fd, HELP_TEXT);
    NSDictionary *err = noff_json_error(TOOL_NAME, subcmd, NOFF_ERR_INVALID_ARGS, @"Unknown command. Use --help.");
    noff_emit_json(stdout_fd, err, compact, quiet);
    return NOFF_EXIT_INVALID_ARGS;
}

void stickers_offload_register(void) {
    int err = native_offload_add_handler("minis-stickers", stickers_handler);
    if (err == 0) {
        noff_ensure_guest_stub("/usr/local/bin/minis-stickers");
        NSLog(@"NativeOffloads: minis-stickers handler registered");
    } else {
        NSLog(@"NativeOffloads: failed to register minis-stickers handler (err=%d)", err);
    }
}
