"""
    format_message_counts(i, n)

If `n==1` returns `""`, otherwise `"\n\n[\$i / \$n]"`.
"""
function format_message_counts(i, n)
    return n == 1 ? "" : "\n\n[$i / $n]"
end

# Combine `N` strings into `M <= N` strings, by concatenating consecutive strings, such that
# each of the resulting strings has length `<= max_length`, unless the input string was already
# longer than `max_length` , in which case it is passed on.
#
# The purpose of this is for nicely splitting long lists of attachments.
function combine_texts(texts; max_length=3800, format_message_counts=format_message_counts)
    messages = String[]
    current_message = ""
    current_length = 0
    for text in texts
        new_length = length(text)
        if current_length + new_length > max_length
            # Finish current message; start new one
            if !isempty(current_message)
                push!(messages, current_message)
            end
            current_message = text
            current_length = new_length
        else
            # Add to current message
            current_message *= text
            current_length += new_length
        end
    end
    # Add last message
    if !isempty(current_message)
        push!(messages, current_message)
    end

    # Add [i / n] tags
    n = length(messages)
    for i in eachindex(messages)
        messages[i] *= format_message_counts(i, n)
    end
    return messages
end