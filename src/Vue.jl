module Vue

using WebIO, JSExpr

export vue, Observable, on, @js, @js_str, @dom_str

"""
`vue(template, data=Dict(); kwargs...)`

Create a Vue instance of `template`, and fill it with `data`.

# Arguments

- `template` the `Node` that acts as the template for the vue instance. See [Vue syntax](https://vuejs.org/v2/guide/syntax.html)
- `data` is either a dictionary or an array of `propertyName => value` pairs.
  If a property's value is an observable, this function automatically sets up Julia -> JS communication.
  To set up JS to Julia communication set up an event handler on `scope[propertyName]` (by calling `on(f, scope[propertyName])`)
  _before_ rendering the scope.

You can pass any other options for the [Vue constructor](https://vuejs.org/v2/guide/instance.html) as keyword arguments to
`vue` E.g. `vue(...; methods=Dict(:sayhello=>@js function(){ alert("hello!") }))`
"""
function vue(template, data=Dict(); kwargs...)
    vuedata = Dict()
    for (k, v) in data
        skey = string(k)
        vuedata[skey] = isa(v, Observable) ? v[] : v
    end

    options = Dict{Any,Any}("data"=>vuedata)
    merge!(options, Dict{Any,Any}(kwargs))

    # This Node is just a placeholder, to enable the real node to be created with
    # WebIO.showcbs[n], once the element id is known. This allows re-displaying
    # a Component with a new element/widget id
    id = WebIO.newid("vue-component")
    widget = Scope(id; imports=Any["vue" => "/pkg/Vue/vue.js"])
    widget.dom = template

    watches = Dict()
    for (k, v) in data
        skey = string(k)
        if isa(v, Observable)
            # associate the observable with the widget
            setobservable!(widget, skey, v)

            # forward updates from Julia to the Vue property, Vue watches the
            # this.vue object's data properties, and updates its view when
            # they change
            onjs(v, @js function (val)
                # This copy is needed to avoid the Vue.js reactivity system
                @var valcopy = JSON.parse(JSON.stringify(val))
                if !(val === this.vue[$skey] || this.arrays_and_equal(val, this.vue[$skey]) ||
                    (val !== val && this.vue[$skey] !== this.vue[$skey]))

                    this.vue[$skey] = valcopy
                    this.valueFromJulia[$skey] = true
                end
            end)

            # Forward vue updates back to WebIO observable, which will send it
            # to Julia iff the the observable's sync property is true
            watches[skey] =
                @js this.vue["\$watch"]($skey, function (val, oldval)
                    # This copy is needed to avoid Vue.js reactivity system
                    @var valcopy = JSON.parse(JSON.stringify(val))
                    if !(self.valueFromJulia[$skey] == true)
                        $v[] = valcopy
                    end
                    self.valueFromJulia[$skey] = false
                end)
        end
    end

    array_equality = js"""
    this.arrays_and_equal = function (arr1, arr2) {
        if (!(Array.isArray(arr1)) || !(Array.isArray(arr2)))
            return false
        var length = arr1.length
        if (length !== arr2.length) return false
        for (var i = 0; i < length; i++)
            if (arr1[i] !== arr2[i])
                return false
        return true
    }
    """

    ondeps_fn = @js function (Vue)
        console.log("initialising "+$id)
        @var options = $options
        options.el = this.dom
        @var self = this
        $array_equality
        function init()
            this.vue = @new Vue(options)
            this.valueFromJulia = Dict()
            $(values(watches)...)
        end
        setTimeout(() -> init.call(self), 0)
    end

    # run the `ondeps_fn` when dependencies are loaded
    onimport(widget, ondeps_fn)
    widget
end

end # module
