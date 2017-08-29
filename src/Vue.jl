module Vue

using WebIO

export vue, Observable, on, @js, @js_str, @dom_str

const noopjs = (@js function() end)

const vue_deps = [Dict("url"=>"vue", "type"=>"js")]
# Run before dependencies are loaded to set up js paths
const systemjs_config_vue = Dict(
    "paths"=>Dict("vue"=>"https://gitcdn.xyz/repo/vuejs/vue/v2.4.2/dist/vue.js")
)
const vue_predeps_fn = @js function ()
    SystemJS.config($systemjs_config_vue)
end

"""
```
vue(template, data=Dict(); dependencies=vue_deps,
    run_predeps=vue_predeps_fn, run_ondeps=noopjs, run_post=noopjs,
    kwargs...)
```
You can pass any other options for the [Vue constructor](https://vuejs.org/v2/guide/instance.html) as keyword arguments to
vue E.g. `vue(...; methods=Dict(:sayhello=>@js function(){ alert("hello!") }))`

Vue instance creation callback functions:
`run_predeps()`: runs before dependencies are loaded, so can be used to specify
dependency paths for example.
`run_ondeps(Vue, Dep_Modules...)`: runs after dependencies are loaded, but
before the Vue instance is created. Can be used to initialise component
libraries for the Vue instance. Arguments passed to run_ondeps are the Vue instance,
then any module objects of the JS libs specified in dependencies.
`run_post(Vue, Dep_Modules...)`: runs after the Vue instance is created.

For all the above JS functions `this` is set to the Widget instance. In run_post
this.vue will refer to the current Vue instance.
"""
function vue(template, data=Dict(); dependencies=vue_deps,
             run_predeps=vue_predeps_fn, run_ondeps=noopjs, run_post=noopjs,
             kwargs...)
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
    n = dom"div"()

    # `display_new_instance` will be called when `show` is called on `n`
    WebIO.showcbs[n] = function display_new_instance(parent_id=WebIO.newid("node"))
        vueid = id*"-$parent_id"
        wrapper = Widget(vueid; dependencies=dependencies)
        nnew = wrapper(dom"div#$vueid"(template))

        # Run callback before dependencies are loaded, e.g. to set up SystemJS config
        onjs(wrapper, "preDependencies", run_predeps)

        watches = Dict()
        for (k, v) in data
            skey = string(k)
            if isa(v, Observable)
                # associate the observable with the widget wrapper
                setobservable!(wrapper, skey, v)

                # forward updates from Julia to the Vue property, Vue watches the
                # this.vue object's data properties, and updates its view when
                # they change
                onjs(v, @js (val) -> (this.vue[$skey] = val))

                # Forward vue updates back to WebIO observable, which will send it
                # to Julia iff the the observable's sync property is true
                watches[skey] = @js this.vue["\$watch"]($skey, function (newval, oldval)
                    $v[] = newval
                end)
            end
        end

        options["el"] = "#$vueid"

        ondeps_fn = @js function (Vue)
            # `this` is set to the JS Widget instance here. `arguments` is an
            # array of the module objects, loaded from `dependencies`
            ($run_ondeps).apply(this, arguments)
            console.log("initialising "+$vueid)
            this.vue = @new Vue($options)
            $(values(watches)...)
            ($run_post).apply(this, arguments)
        end

        # run the `ondeps_fn` when dependencies are loaded
        ondependencies(wrapper, ondeps_fn)
        nnew
    end
    n
end

end # module
