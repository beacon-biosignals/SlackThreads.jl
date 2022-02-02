"""
    message_count_suffix(i, n)

If `n==1` returns `""`, otherwise `"\n\n[\$i / \$n]"`.
"""
function message_count_suffix(i, n)
    return n == 1 ? "" : "\n\n[$i / $n]"
end

"""
    combine_texts(texts; max_length=3800, message_count_suffix=message_count_suffix) -> Vector{String}

Combine `N` strings in `texts` into `M <= N` strings, by concatenating consecutive strings, such that
each of the resulting strings has length `<= max_length`, unless the input string was already
longer than `max_length` , in which case it is passed on.

The purpose of this is for nicely splitting long lists of attachments.

The keyword argument `message_count_suffix` defaults to [`SlackThreads.message_count_suffix`](@ref), and is used
for formatting the suffix of messages in the case that a message needs to split into multiple messages.
"""
function combine_texts(texts; max_length=3800, message_count_suffix=message_count_suffix)
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
        messages[i] *= message_count_suffix(i, n)
    end
    return messages
end
