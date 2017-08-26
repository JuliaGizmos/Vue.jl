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
    id = WebIO.newid("vue-instance")

    wrapper = Widget(id,
        dependencies=dependencies
    )

    init = Dict()
    watches = Dict()

    for (k, v) in data
        skey = string(k)
        if isa(v, Observable)
            setobservable!(wrapper, skey, v)

            # forward updates from Julia to the Vue property
            onjs(v, @js (val) -> (this.vue[$skey] = val))

            # forward vue updates back to WebIO observable
            # which might send it to Julia
            watches[skey] = @js this.vue["\$watch"]($skey, function (newval, oldval)
                # `this` is the vue instance in here
                $v[] = newval
            end)
            init[skey] = v[]
        else
            init[skey] = v
        end
    end

    options = merge(Dict("el"=>"#$id", "data"=>init), Dict(kwargs))

    # Run before dependencies are loaded, e.g. to set up SystemJS config
    onjs(wrapper, "preDependencies", run_predeps)

    ondeps_fn = @js function (Vue)
        # `this` is set to the JS Widget instance, if other deps have been
        # specified then
        ($run_ondeps).apply(this, arguments)
        this.vue = @new Vue($options)
        $(values(watches)...)
        ($run_post).apply(this, arguments)
    end

    ondependencies(wrapper, ondeps_fn)

    wrapper(dom"div#$id"(template))
end

end # module
