{application, example,
  [{description, "An example application"},
   {vsn, "0.1.0"},
   {modules, [example_app, example_sup]},
   {registered, [example_registry]},
   {applications, [kernel, stdlib]},
   {mod, {example_app, []}}
  ]}.
