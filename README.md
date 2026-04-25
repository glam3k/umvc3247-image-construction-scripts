# umvc3247-image-construction-scripts

Public bootstrap and image-construction scripts for the UMVC3247 environment.

## Layout

- `src/windows`: Windows image-prep and payload scripts
- `src/linux`: Linux bootstrap scripts and shared shell helpers

## Notes

- This repo is intended to stay public so fresh machines can fetch bootstrap payloads without requiring access to the private application repo.
- Keep secrets, private runtime assets, and application-specific business logic out of this repository.
