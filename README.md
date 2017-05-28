# Vue.jl

A Julia wrapper for [Vue.js](https://vuejs.org).

## Usage

```julia
using Vue
WebIO.setup()

template = dom"p[v-if=visible]"("{{message}}")
vue(template, [:message=>"hello", :visible=>true])
```

You can also pass in observables as properties in which case they are synced between Julia and JavaScript:

```julia
ob = Observable("hello")
vue(template, [:message=ob, :visible=true])
```

Now if at any time you run `ob[] = "hey there!"` on Julia, you should see the contents of the message update in the UI.

```julia
incoming = Observable("")
on(println, incoming) # print to console on every update

template = dom"input[type=text,v-model=message]"(message=incoming)
vue(template, [:message=ob, :visible=true])
```

This will cause the value of the textbox to flow back to Julia, and should get printed to STDOUT since we have a listener to print it.

You can pass any other options for the [`Vue` constructor](https://vuejs.org/v2/guide/instance.html) as keyword arguments to `vue`.
