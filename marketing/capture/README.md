# App Store screenshot capture

This folder generates 1242x2688 App Store screenshots from static HTML layouts.

## Inputs

Add four raw app screenshots beside this file:

```text
s1.png
s2.png
s3.png
s4.png
```

The HTML falls back to labeled placeholders until those files exist.

## Generate

```bash
npm install
npm run capture
```

Outputs are written beside the templates:

```text
screenshot-1.png ... screenshot-4.png
```
