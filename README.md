# Vue.jl

A Julia wrapper for [Vue.js](https://vuejs.org). It uses [WebIO](https://github.com/JuliaGizmos/WebIO.jl) to load JavaScript and to do Julia to JS communication. [Go here](https://github.com/JuliaGizmos/WebIO.jl/blob/master/README.md) to get started with WebIO.

## Usage

The package exports a single `vue` function which mirrors the [Vue instance constructor](https://vuejs.org/v2/guide/instance.html):

### `vue(template, data; options...)`


- `template` acts as the template for the vue instance. See [Vue's HTML-based syntax](https://vuejs.org/v2/guide/syntax.html). You can compose the template (like any HTML) [using WebIO](https://github.com/JuliaGizmos/WebIO.jl#composing-content).
- `data` is an iterable of `propertyName => value` pairs (e.g. a `Dict`) which populates the template.

```julia
using Vue

template = dom"p[v-if=visible]"("{{message}}")
vue(template, [:message=>"hello", :visible=>true])
```

If a property's value is an observable, this function syncs the property and the observable. Here's how you can update the properties bound to the template from Julia.

```julia
ob = Observable("hello")
vue(template, [:message=>ob, :visible=>true])
```
Now if at any time you run `ob[] = "hey there!"` on Julia, you should see the contents of the message update in the UI. Try making an observable for `:visible` property and set it to true or false, you should see the message toggle in and out of view!

To initiate JS to Julia communication you must set an event handler on `scope[propertyName]` (by calling `on(f, scope[propertyName])`)  _before_ rendering the scope.

Here's an example of JS to Julia communication:

```julia
incoming = Observable("")
on(println, incoming) # print to console on every update

template = dom"input[type=text,v-model=message]"()
vue(template, [:message=>incoming])
```

This will cause the value of the textbox to flow back to Julia, and should get printed to STDOUT since we have a listener to print it.

You can pass _any_ other options for the [Vue constructor](https://vuejs.org/v2/guide/instance.html) as keyword arguments to
`vue` E.g. `vue(...; methods=Dict(:sayhello=>@js function(){ alert("hello!") }))` (Tip: use [JSExpr.jl](https://github.com/JuliaGizmos/JSExpr.jl) for the `@js` macro)

That's it! :-)
