module VueJS

using WebIO

function vue(template; kwargs...)
    id = WebIO.newid("vue-instance")

    wrapper = Widget(id,
        dependencies=[Dict("url"=>"https://unpkg.com/vue", "type"=>"js")]
    )

    data = Dict()
    watches = Dict()

    for (k, v) in kwargs
        skey = string(k)
        if isa(v, Observable)
            setobservable!(wrapper, skey, v)

            # forward updates from Julia to the Vue property
            onjs(v, @js (ctx, val) -> ctx.vue[$skey] = val)

            # forward vue updates back to WebIO observable
            watches[skey] = @js ctx.vue["\$watch"]($skey, function (newval, oldval)
                                        $ob[] = newval
                                       end)
            data[skey] = v[]
        else
            data[skey] = v
        end
    end

    after(wrapper, "dependenciesLoaded", @js function (deps, ctx)
            @var Vue = deps[0];
            ctx.vue = @new Vue(d(el=$("#$id"),
                  data=$data
                 )
               )
            $(values(watches)...)
          end)

    wrapper(dom"div"(template, id=id))
end

end # module
