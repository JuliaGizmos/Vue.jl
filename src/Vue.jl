module Vue

using WebIO

export vue

function vue(template, data=[]; kwargs...)
    id = WebIO.newid("vue-instance")

    wrapper = Widget(id,
        dependencies=[Dict("url"=>"https://unpkg.com/vue", "type"=>"js")]
    )

    init = Dict()
    watches = Dict()

    for (k, v) in data
        skey = string(k)
        if isa(v, Observable)
            setobservable!(wrapper, skey, v)

            # forward updates from Julia to the Vue property
            onjs(v, @js (ctx, val) -> ctx.vue[$skey] = val)

            # forward vue updates back to WebIO observable
            # which might send it to Julia
            watches[skey] = @js ctx.vue["\$watch"]($skey, function (newval, oldval)
                                           WebIO.setval($ob, newval, true)
                                       end)
            init[skey] = v[]
        else
            init[skey] = v
        end
    end

    options = merge(Dict("el"=>"#$id", "data"=>init), Dict(kwargs))

    after(wrapper, "dependenciesLoaded", @js function (deps, ctx)
            @var Vue = deps[0];
            ctx.vue = @new Vue($options)
            $(values(watches)...)
          end)

    wrapper(dom"div"(template, id=id)) # FIXME why can't I set the ID on the class?
end

end # module
