const DEFAULT_INTERRUPT_TEXT = """
                       `InterruptException` recieved.

                       Probably you know about this already.
                       """

default_exception_text(exception, backtrace) = """
            :alert: Error occured! :alert:

            ```
            $(sprint(Base.display_error, exception, backtrace))
            ```
            """

"""
    slack_log_exception(f, thread::SlackThread; interrupt_text=DEFAULT_INTERRUPT_TEXT,
                        exception_text=default_exception_text)
    slack_log_exception(thread::SlackThread, exception, backtrace;
                        interrupt_text=DEFAULT_INTERRUPT_TEXT,
                        exception_text=default_exception_text)

Log an exception (and stacktrace) to a `SlackThread`. Can be used with a zero-argument
function `f`, as in

```julia
slack_log_exception(thread) do
    sqrt(-1)
end
```

or given an `exception` and `backtrace` explictly, as in
```julia
try
    sqrt(-1)
catch exception
    slack_log_exception(thread, exception, catch_backtrace())
    # do other error handling...
end
```

## Optional arguments

* Pass `interrupt_text::AbstractString` to customize the message sent when an `InterruptException` is caught. See `SlackThreads.DEFAULT_INTERRUPT_TEXT` for the default text.
* Pass a two-argument function `exception_text` to customize the message shown for a general exception, where the arguments are `exception` and `backtrace`.
"""
function slack_log_exception(f, thread::SlackThread; interrupt_text=DEFAULT_INTERRUPT_TEXT,
                             exception_text=default_exception_text)
    try
        f()
    catch exception
        slack_log_exception(thread, exception, catch_backtrace(); interrupt_text,
                            exception_text)
        rethrow()
    end
end

function slack_log_exception(thread::SlackThread, exception, backtrace;
                             interrupt_text=DEFAULT_INTERRUPT_TEXT,
                             exception_text=default_exception_text)
    @maybetry begin
        msg = exception isa InterruptException ? interrupt_text :
              exception_text(exception, backtrace)
        send_message(thread, msg)
    end "Error when logging exception to Slack."
    return nothing
end
