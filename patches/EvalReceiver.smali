.class public final Lzz/EvalReceiver;
.super Landroid/content/BroadcastReceiver;
.source "EvalReceiver.java"

# PATCH adblock-inject (--devtools builds only)
# Receives "dev.utv.runtime.EVAL" broadcasts from `utv-runtime eval` and runs the base64 "js64" extra
# in the page through AdBlockObserver.evaluate. Results come back over the title log channel.
# Exported on purpose so adb can reach it, which also means any app on the TV can inject JS:
# never ship this in an everyday build.

.field private static registered:Z

.field private final observer:Lzz/AdBlockObserver;


.method public constructor <init>(Lzz/AdBlockObserver;)V
    .locals 0

    invoke-direct {p0}, Landroid/content/BroadcastReceiver;-><init>()V
    iput-object p1, p0, Lzz/EvalReceiver;->observer:Lzz/AdBlockObserver;
    return-void
.end method


# Register once per process. The application context comes from ActivityThread.currentApplication()
# so no app class (and no obfuscated name) is needed.
.method public static register(Lzz/AdBlockObserver;)V
    .locals 4

    sget-boolean v0, Lzz/EvalReceiver;->registered:Z
    if-nez v0, :done

    :try_start
    const-string v0, "android.app.ActivityThread"
    invoke-static {v0}, Ljava/lang/Class;->forName(Ljava/lang/String;)Ljava/lang/Class;
    move-result-object v0
    const-string v1, "currentApplication"
    const/4 v2, 0x0
    new-array v3, v2, [Ljava/lang/Class;
    invoke-virtual {v0, v1, v3}, Ljava/lang/Class;->getMethod(Ljava/lang/String;[Ljava/lang/Class;)Ljava/lang/reflect/Method;
    move-result-object v0
    const/4 v1, 0x0
    new-array v3, v2, [Ljava/lang/Object;
    invoke-virtual {v0, v1, v3}, Ljava/lang/reflect/Method;->invoke(Ljava/lang/Object;[Ljava/lang/Object;)Ljava/lang/Object;
    move-result-object v0
    check-cast v0, Landroid/content/Context;

    new-instance v1, Lzz/EvalReceiver;
    invoke-direct {v1, p0}, Lzz/EvalReceiver;-><init>(Lzz/AdBlockObserver;)V
    new-instance v2, Landroid/content/IntentFilter;
    const-string v3, "dev.utv.runtime.EVAL"
    invoke-direct {v2, v3}, Landroid/content/IntentFilter;-><init>(Ljava/lang/String;)V
    # 0x2 = Context.RECEIVER_EXPORTED (required on Android 14+, ignored before).
    const/4 v3, 0x2
    invoke-virtual {v0, v1, v2, v3}, Landroid/content/Context;->registerReceiver(Landroid/content/BroadcastReceiver;Landroid/content/IntentFilter;I)Landroid/content/Intent;

    const/4 v0, 0x1
    sput-boolean v0, Lzz/EvalReceiver;->registered:Z
    const-string v0, "utv-runtime"
    const-string v1, "eval receiver registered"
    invoke-static {v0, v1}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I
    :try_end
    .catch Ljava/lang/Throwable; {:try_start .. :try_end} :failed

    :done
    return-void

    :failed
    move-exception v0
    const-string v1, "utv-runtime"
    const-string v2, "eval receiver registration failed"
    invoke-static {v1, v2, v0}, Landroid/util/Log;->w(Ljava/lang/String;Ljava/lang/String;Ljava/lang/Throwable;)I
    return-void
.end method


.method public final onReceive(Landroid/content/Context;Landroid/content/Intent;)V
    .locals 3

    :try_start
    const-string v0, "js64"
    invoke-virtual {p2, v0}, Landroid/content/Intent;->getStringExtra(Ljava/lang/String;)Ljava/lang/String;
    move-result-object v0
    if-eqz v0, :done

    const/4 v1, 0x0
    invoke-static {v0, v1}, Landroid/util/Base64;->decode(Ljava/lang/String;I)[B
    move-result-object v0
    new-instance v1, Ljava/lang/String;
    sget-object v2, Ljava/nio/charset/StandardCharsets;->UTF_8:Ljava/nio/charset/Charset;
    invoke-direct {v1, v0, v2}, Ljava/lang/String;-><init>([BLjava/nio/charset/Charset;)V

    iget-object v0, p0, Lzz/EvalReceiver;->observer:Lzz/AdBlockObserver;
    invoke-virtual {v0, v1}, Lzz/AdBlockObserver;->evaluate(Ljava/lang/String;)V
    :try_end
    .catch Ljava/lang/Throwable; {:try_start .. :try_end} :failed

    :done
    return-void

    :failed
    move-exception v0
    const-string v1, "utv-runtime"
    const-string v2, "eval failed"
    invoke-static {v1, v2, v0}, Landroid/util/Log;->w(Ljava/lang/String;Ljava/lang/String;Ljava/lang/Throwable;)I
    return-void
.end method
