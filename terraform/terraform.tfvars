# Non-secret values for the live Roastfolio project. The Apify token is never here.
project_id  = "ai-experiments-487722"
region      = "us-central1"
alert_email = "aacs85@gmail.com"
github_repo = "ykro/roastfolio"

# Filled after authorizing the GitHub connection in the browser (see README):
#   gcloud builds connections describe rf-github --region=us-central1 \
#     --format='value(githubConfig.appInstallationId,githubConfig.authorizerCredential.oauthTokenSecretVersion)'
github_app_installation_id = 165805031
github_token_secret        = "rf-github-github-oauthtoken-07fca8"
