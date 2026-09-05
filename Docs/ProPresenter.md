# Working With ProPresenter

`pro-crud` prepares document files for ProPresenter. Use ProPresenter to import
those files and manage live presentation output.

## Importing Bundles

In ProPresenter 21.4, importing a `.probundle` whose internal `.pro` filename
matches an existing presentation can replace that presentation while leaving
cached thumbnails from the previous version visible. Use a unique internal
`.pro` filename when importing a separate revision. Renaming only the bundle
does not change that internal filename.

See [presentation documents](Format/PresentationDocuments.md#minimal-authored-presentation)
for import requirements and normalization behavior.
