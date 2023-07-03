# VDOM3

## What is this?

This is an attempt at making a better VDOM for [Mayu Live](https://github.com/mayu-live/framework).

## Planned features

### Resumability

It should be possible to serialize the entire tree and then deserialize it
and continue to run it on another instance.
This will be done using the [Marshal module](https://docs.ruby-lang.org/en/3.2/Marshal.html).

### Custom elements

Pages should first render as regular HTML, sent to the browser,
and then whenever new components render during runtime,
they should load cacheable HTML templates from the server.

Not 100% sure how this should work in reality.
There is the [declarative shadow DOM](https://developer.chrome.com/en/articles/declarative-shadow-dom/),
but it's not supported in Firefox yet, and I think it would be way too noisy.

```html
<my-element>
  <template shadowrootmode="open">
    <style>@import url('/assets/my-element.css');</style>
    <h2>Hello world</h2>
    <slot></slot>
  </template>
  <p>foo</p>
</my-element>
<my-element>
  <template shadowrootmode="open">
    <style>@import url('/assets/my-element.css');</style>
    <h2>Hello world</h2>
    <slot></slot>
  </template>
  <p>bar</p>
</my-element>
```

This should be basically the same as:

```html
<h2>Hello world</h2>
<p>foo</p>
<h2>Hello world</h2>
<p>bar</p>
```

But it takes a lot more space, so I'm not really sure.

It would be possible to render something like:

```html
<my-element>
  <h2>Hello world</h2>
  <p>foo</p>
</my-element>
<my-element>
  <h2>Hello world</h2>
  <p>bar</p>
</my-element>
```

And then when the template for my-element has been loaded into the shadow root
of my-element, it would figure out that the h2 should be removed from the list
of children since it's already in the template.

However, by doing it this way, it wouldn't be possible to have styling scoped
to the elements shadow root until it has loaded...
