define ["alertParser"], (parser) ->
    opTree =
        ">": (e, n) -> (e.v(n.left) > e.v(n.right))
        "<": (e, n) -> (e.v(n.left) < e.v(n.right))
        ">=": (e, n) -> (e.v(n.left) >= e.v(n.right))
        "<=": (e, n) -> (e.v(n.left) <= e.v(n.right))
        "=": (e, n) -> (e.v(n.left) == e.v(n.right))
        "c": (e, n) -> n.constant
        "alert": (e, n) -> e.v({
                op: n.compare,
                left: { op: 'c', constant: e.getCurrentValue() },
                right: n.expr })


    class AlertEvaluation
        constructor: (tree, inputs) ->
            @tree = tree
            @inputs = inputs


        eval: () ->
            return @v(@tree)


        getCurrentValue: () ->
            return @inputs.currentValue


        v: (node) ->
            return opTree[node.op](@, node)


    class AlertEvaluator
        constructor: (expr) ->
            @tree = parser.parse(expr)


        eval: (inputs) ->
            ae = new AlertEvaluation(@tree, inputs)
            return ae.eval()
