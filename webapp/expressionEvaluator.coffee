define ["expressionParser"], (parser) ->

    # The opTree maps the "op" key in each member to a function that
    # takes the node evaluator "e" and the current node "n" and returns
    # a numeric result.
    opTree =
        "c": (e, n) -> n.constant
        "s": (e, n) -> e.statValue(n.statName)
        "limitedStat": (e, n) -> e.statValue(n.stat.statName, n.limits)
        "+": (e, n) -> e.v(n.left) + e.v(n.right)
        "-": (e, n) -> e.v(n.left) - e.v(n.right)
        "*": (e, n) -> e.v(n.left) * e.v(n.right)
        "/": (e, n) -> e.v(n.left) / e.v(n.right)
        "call": (e, n) ->
            funcs =
                "min": Math.min
                "max": Math.max
            func = funcs[n.func]
            args = []
            for a in n.args
                args.push(e.v(a))
            return func.apply(Math, args)
        "forEach-sum": (e, n) ->
            subevals = e.splitByGroup(n.group)
            total = 0.0
            allNaN = true
            for g, subeval of subevals
                # Move the subeval up to our current point
                subeval.dataPoint = e.dataPoint
                val = subeval.v(n.expr)
                if not isNaN(val)
                    total += val
                    allNaN = false
            if allNaN
                total = NaN
            return total
            
    getValueAsRegex = (v) ->
        if v.op == "value"
            return new RegExp('^' + v.value + '$')
        else if v.op == "regex"
            return new RegExp('^' + v.regex + '$')
        else
            throw "Unknown value type: #{ v.op }"
            
    statLimitTree =
        "groupEqual": (q, n) -> getValueAsRegex(n.value).test(q.groups[n.group])

    class NodeEvaluator
        constructor: (exprTree, dataSets, statsController) ->
            ### exprTree - Parsed tree to evaluate.
            dataSets - actually a dataGroup's values member
            ###
            @dataSets = dataSets
            @dataPoint = 0
            @statsController = statsController
            @exprTree = exprTree
            # Cache splitByGroup calls
            @_splittings = {}


        eval: (pt) ->
            ### Evaluate @dataSets at point pt
            ###
            @dataPoint = pt
            return @v(@exprTree)
            
            
        splitByGroup: (g) ->
            ### Split @dataSets according to group g; output is dict:
            { 'grouping': NodeEvaluator for slice }
            ###
            if g of @_splittings
                return @_splittings[g]
            subsets = {}
            for stat, statSets of @dataSets
                for statSet in statSets
                    gval = statSet.groups[g]
                    if gval not of subsets
                        subsets[gval] = {}
                    if stat not of subsets[gval]
                        subsets[gval][stat] = []
                    subsets[gval][stat].push(statSet)
                    
            evals = {}
            for group, data of subsets
                evals[group] = new NodeEvaluator(null, data, @statsController)
            @_splittings[g] = evals
            return evals
            
            
        statValue: (s, sLimits) ->
            sv = 0.0
            stat = @statsController.stats[s]
            if not @dataSets[s]?
                # No data, return 0
                return sv

            # Since we log non-existent stats as NaN, but filters defined in
            # sLimits should only result in a zero return, not NaN, we need
            # to keep track of if there could have been any goodValues
            # separately from if there were goodValues.
            hadGoodValue = false
            goodValues = []
            for q in @dataSets[s]
                val = q.values[@dataPoint]
                if isNaN(val)
                    continue
                hadGoodValue = true
                if not @testLimit(q, sLimits)
                    continue
                goodValues.push(val)
                
            if goodValues.length == 0
                # No values passing filters, return NaN
                if not hadGoodValue
                    return NaN
                return sv

            if stat.type == 'total-max'
                sv = null
                for val in goodValues
                    if sv == null or sv < val
                        sv = val
            else if stat.type == 'total-avg'
                svCount = 0
                for val in goodValues
                    sv += val
                    svCount += 1
                sv /= svCount
            else
                for val in goodValues
                    sv += val
            return sv


        testLimit: (dataSet, sLimits) ->
            ### Return true if this dataSet adheres to the given limits; false
            if it does not.
            ###
            if not sLimits?
                # No limits - everything's ok!
                return true
            for l in sLimits
                if not statLimitTree[l.op](dataSet, l)
                    return false
            return true


        v: (node) ->
            return opTree[node.op](@, node)


    class Expression
        constructor: (parsed) ->
            @tree = parsed


        eval: (dataSetOut, values, statsController, pointTimes) ->
            ### Returns the evaluated expression for all points in values at
            the given pointTimes.
            ###
            evaluator = new NodeEvaluator(@tree, values, statsController)
            for j in [0...pointTimes.length]
                x = pointTimes[j]
                y = evaluator.eval(j)
                dataSetOut.push(
                    x: x
                    y: y
                )


    ### Compiles and evaluates an expression.
    ###
    ExpressionEvaluator =
        compile: (expr) ->
            # Compile an Expression object based on expr
            return new Expression(parser.parse(expr))

    ExpressionEvaluator.parser = parser
    return ExpressionEvaluator

