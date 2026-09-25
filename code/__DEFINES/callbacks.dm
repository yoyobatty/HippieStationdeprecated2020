#define GLOBAL_PROC	"some_magic_bullshit"

#define CALLBACK new /datum/callback
#define INVOKE_ASYNC world.ImmediateInvokeAsync
#define CALLBACK_NEW(typepath, args) CALLBACK(GLOBAL_PROC, /proc/___callbacknew, typepath, args)

// Proc references for callbacks, signals, timers and call().
// Since BYOND 515 a raw `.proc/foo` or `/type.proc/foo` is bound to that exact proc at compile time,
// so calling it on a subtype that overrides foo() silently runs the parent's version instead.
// nameof() turns the reference into the proc's name, which call() resolves on the object at runtime,
// so overrides are honored again. The compiler still errors if the proc doesn't exist.
/// Reference to a proc on src's type (or a parent of it), dispatched by name.
#define PROC_REF(X) (nameof(.proc/##X))
/// Reference to a verb on src's type (or a parent of it), dispatched by name.
#define VERB_REF(X) (nameof(.verb/##X))
/// Reference to a proc on the given type (or a parent of it), dispatched by name.
#define TYPE_PROC_REF(TYPE, X) (nameof(##TYPE.proc/##X))
/// Reference to a verb on the given type (or a parent of it), dispatched by name.
#define TYPE_VERB_REF(TYPE, X) (nameof(##TYPE.verb/##X))
/// Reference to a global proc. Stays a real proc path, since call() needs one for global procs.
#define GLOBAL_PROC_REF(X) (/proc/##X)
