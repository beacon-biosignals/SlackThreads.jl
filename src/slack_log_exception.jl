function slack_log_exception(f, thread::SlackThread; interrupt_text=INTERRUPT_TEXT,
                             exception_text=exception_text)
    try
        f()
    catch exception
        slack_log_exception(thread, exception, catch_backtrace(); interrupt_text,
                            exception_text)
        rethrow()
    end
end

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

function slack_log_exception(thread, exception, backtrace;
                             interrupt_text=DEFAULT_INTERRUPT_TEXT,
                             exception_text=default_exception_text)
    @maybetry begin
        msg = exception isa InterruptException ? interrupt_text :
              exception_text(exception, backtrace)
        send_message(thread, msg)
    end "Error when logging exception to Slack."
    return nothing
end
