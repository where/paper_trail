The following changes happened from the airblade branch:

- Remove the has_one relation reification.  Seems weird to have belongs_to relations work substantially different than has_one relations.  In our project we need all types of relation version control.
- Support the following case:

```
i = Item.create
v = i.versions.first
i.destroy
v.reify
```

In the upstream version v.reify will be nil.  This a series of use cases not possible.

- On reification store the version object.  This is so a reified object can look at the meta data that is stored in the version table.

- Fix a bug in reify when an attribute has been removed but there is still a setter method.
