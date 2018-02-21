module Vue

using WebIO

export vue, Observable, on, @js, @js_str, @dom_str

"""
```
vue(template, data=Dict(); kwargs...)
```

You can pass any other options for the [Vue constructor](https://vuejs.org/v2/guide/instance.html) as keyword arguments to
vue E.g. `vue(...; methods=Dict(:sayhello=>@js function(){ alert("hello!") }))`
"""
function vue(template, data=Dict(); kwargs...)
    # note that all the code below, except that in `display_new_instance` only
    # runs per component, so if the component is displayed twice it won't be run
    # again.

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
    widget = Widget(id; imports=["https://gitcdn.xyz/cdn/vuejs/vue/v2.4.2/dist/vue.js"])
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
                this.vue[$skey] = valcopy
            end)

            # Forward vue updates back to WebIO observable, which will send it
            # to Julia iff the the observable's sync property is true
            watches[skey] =
                @js this.vue["\$watch"]($skey, function (val, oldval)
                    # This copy is needed to avoid Vue.js reactivity system
                    @var valcopy = JSON.parse(JSON.stringify(val))
                    $v[] = valcopy
                end)
        end
    end

    ondeps_fn = @js function (Vue)
        console.log("initialising "+$id)
        @var options = $options
        options.el = this.dom
        console.log(options)
        @var self = this
        function init()
            this.vue = @new Vue(options)
            $(values(watches)...)
        end
        setTimeout(() -> init.call(self), 0)
    end

    # run the `ondeps_fn` when dependencies are loaded
    onimport(widget, ondeps_fn)
    widget
end

end # module
