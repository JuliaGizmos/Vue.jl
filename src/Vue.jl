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

    id = WebIO.newid("vue-component")

    wrapper = Widget(id,
        dependencies=dependencies
    )

    init = Dict()
    watches = Dict()

    for (k, v) in data
        skey = string(k)
        if isa(v, Observable)
            # associate the observable with the widget wrapper
            setobservable!(wrapper, skey, v)

            # forward updates from Julia to the Vue property, Vue watches the
            # window.vueinfo[$id].data object, and updates view accordingly
            onjs(v, @js (val) -> (window.vueinfo[$id].data[$skey] = val))

            # forward vue updates back to WebIO observable, which might send it
            # to Julia. Note, if the component is rendered multiple times,
            # window.vueinfo[$id].vm will refer to only the first instance. However, all
            # instances will update the shared data object for this component:
            # window.vueinfo[$id].data, and thus the Observable (on the js and Julia
            # sides) and all instances will stay in sync.
            # TODO if the first instance is removed, then no one will be watching,
            # so updates won't come to julia. To fix, store all instances in
            # window.vueinfo[$id].instances and put some updating logic in a
            # Vue({destroyed: }) callback, OR everyone watches and you do smart
            # updating to avoid sending too much (prob harder)
            watches[skey] = @js window.vueinfo[$id].vm["\$watch"]($skey, function (newval, oldval)
                $v[] = newval
            end)
            init[skey] = v[]
        else
            init[skey] = v
        end
    end

    options = merge(Dict("el"=>"#$id", "data"=>(@js window.vueinfo[$id].data)), Dict(kwargs))

    # Run callback before dependencies are loaded, e.g. to set up SystemJS config
    onjs(wrapper, "preDependencies", run_predeps)

    # initialise global Vue state before Vue gets loaded
    onjs(wrapper, "preDependencies", @js function init_vueinfo()
        if (typeof(window.vueinfo) === "undefined" ||
                # julia restart (but js window remains, e.g. ijulia kernel restart)
                ($id === "vue-component-1"))
            console.log("clean Vue.jl slate")
            window.vueinfo = d()
        end
        if (typeof(window.vueinfo[$id]) === "undefined")
            # console.log("init everything")
            window.vueinfo[$id] = d(:data => d())
            window.vueinfo[$id].instance_count = 1
            console.log("initialising data for "+$id)
            window.vueinfo[$id].data = $init
        else
            window.vueinfo[$id].instance_count += 1
        end
        console.log("num instances of "+$id+" is "+window.vueinfo[$id].instance_count)
    end)

    # there will be one Widget instance on the julia side (`wrapper`), but
    # potentially multiples on the js - one for each time the vue component is
    # displayed
    n = wrapper()

    # the below `display_new_instance` will be run when the widget is to be
    # displayed
    WebIO.showcbs[n] = function display_new_instance(io, node_id)
        vueid = id*"-$node_id"
        nnew = append(n, [dom"div#$vueid"(template)])
        options["el"] = "#$vueid"

        ondeps_fn = @js function (Vue)
            # `this` is set to the JS Widget instance here
            # `arguments` is an array of the module objects, loaded from `dependencies`
            ($run_ondeps).apply(this, arguments)
            console.log("initialising "+$vueid)
            this.vue = @new Vue($options)
            if typeof(window.vueinfo[$id].vm) === "undefined"
                window.vueinfo[$id].vm = this.vue
                # console.log("setting watches")
                $(values(watches)...)
            end
            ($run_post).apply(this, arguments)
        end

        # n.b. a new deps promise is created for each displayed instance,
        # `after` only adds the `ondeps_fn` to the latest instance. In contrast,
        # the `onjs` function stores the handlers in julia and thus when a new
        # js instance is displayed, all handlers will be run when the
        # dependenciesLoaded promise resolves, thus we use `after` here to just
        # run the ondeps_fn for the instance we're about to display.
        ondependencies(wrapper, ondeps_fn)
        nnew
    end
    n
end

end # module
