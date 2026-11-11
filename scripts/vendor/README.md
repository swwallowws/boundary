# Vendored

Third-party code boundary's scripts load, copied in unchanged so they run with nothing but Node.

| File | From | Licence |
| --- | --- | --- |
| `js-yaml.mjs` | js-yaml 4.3.2 from npm, `dist/js-yaml.mjs` (package integrity `sha512-SFNOvSJ+Dgf/9An904Yx+CgSlIPCkIpao4qo51lpee25TIRejdH3rhR4EZMGoNx3/TP3O+wzWuiTFl4sqbltzA==`, file sha256 `cea276c7e15f409a1adbe5d177aba7824398a474f7cf702bd57962c7d570636f`) | MIT, `js-yaml.LICENSE` |

To update: `npm pack js-yaml@<version>` into an empty folder, check its integrity against `npm view js-yaml@<version> dist.integrity`, copy `package/dist/js-yaml.mjs` and `package/LICENSE` here and update this table. Then run `./test.sh`.
