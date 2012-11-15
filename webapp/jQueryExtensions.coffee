define ["jquery"], () ->
    $.compareObjs = (a,b) ->
        # Returns true if objects match, false otherwise
        if a == null or b == null
            # typeof null == 'object' for some reason...
            return (a == b)
        if typeof a == typeof b and typeof a == "object"
            for own key of a
                if not b.hasOwnProperty(key)
                    return false
                if not $.compareObjs(a[key], b[key])
                    return false
            for own key of b
                if not a.hasOwnProperty(key)
                    return false
        else if a != b
            return false
        return true

