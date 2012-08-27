invtxt
======

invtxt is a lightweight home inventory script inspired by todotxt

It uses a plaintext file in a human-readble format to store the inventory data and also offers the possibility to integrate pictures of the items and show them on demand.

invtxt has no other requirements than ruby installed on your system (tested with 1.9.3)
ImageMagick is an optional requirement to enable automatic picture shrinking.

invtxt supports categories and tags, similar to Wordpress, which means that an item can have one category and unlimited tags. The category is used to sort the output data, the tags are useful for searching.

invtxt also supports aliases and references to items. You can give unique names to items and refer to them from other items. A usage case would be a container item which references all its contents.

invtxt can save an available and a required amount for each item and list items with a deficit.

Although the format is human-readable, invtxt can pretty-print and colorize the item list in a more structured way.

Usage
-----

When you run invtxt the first time, it will complain that the inventory directory does not exist. Either create the shown directory or change it in the .invtxt config file, which has been created in your home directory.

Run 'invtxt -h', to see a list of all possible actions.

Places where ITEM is expected mean that you should either use the alias name (with or without prefix) or use the line number (the number shown at the beginning of each item).

inv.txt file format
-------------------

optional quantity, e.g.:

```
(2)
(4/7)
```

optional alias ('*' prefix), e.g.:

```
 *myItem
 *someName
```

arbitrary description text (mandatory), e.g:

```
this is some item description text
```

optional meta data section, introduced by '->' and followed by category ('@' prefix), tags ('#' prefix), references to other items by their alias name and picture references ('+' prefix, appended automatically), e.g:

```
@category #some #tags *otherItem1 *otherItem2
```

some example item entries:

```
(2/5) T-Shirts -> @home #clothing *favShirt
*favShirt My favorite blue shirt -> +1
a minimal item entry
```
