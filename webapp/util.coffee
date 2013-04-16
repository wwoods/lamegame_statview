define [], () ->
    util =
        deepEquals: (a, b) ->
            if typeof(a) != typeof(b)
                return false
            else if $.isArray(a) and $.isArray(b)
                if a.length != b.length
                    return false
                for v, i in a
                    if not util.deepEquals(v, b[i])
                        return false
            else if typeof(a) == 'object'
                for k, v of a
                    if not util.deepEquals(v, b[k])
                        return false
                for k, v of b
                    if not (k of a)
                        return false
            else if a != b
                return false
            return true
