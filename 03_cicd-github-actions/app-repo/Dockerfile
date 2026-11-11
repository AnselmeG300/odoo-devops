# =============================================================================
# Image Odoo personnalisee EAZY Training
# =============================================================================
# On part de l'image officielle Odoo (celle utilisee telle quelle au Sprint 1)
# et on y ajoute nos addons maison. C'est cette image, taguee avec le SHA du
# commit, que la CI construit et pousse, et que la CD deploie via Carvel.
# =============================================================================
FROM odoo:19.0

# Metadonnees de tracabilite (remplies par la CI avec les valeurs du build)
ARG VCS_REF=dev
ARG BUILD_DATE=unknown
LABEL org.opencontainers.image.title="odoo-custom-eazy" \
      org.opencontainers.image.source="https://github.com/AnselmeG300/odoo-devops" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.created="${BUILD_DATE}"

# Copie des addons maison dans le chemin lu par Odoo
COPY addons /mnt/extra-addons

# On reste sur l'utilisateur non-root fourni par l'image officielle
USER odoo
