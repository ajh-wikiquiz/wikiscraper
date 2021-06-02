terraform {
  required_providers {
    heroku = {
      source  = "heroku/heroku"
      version = "~> 4.0"
    }
  }
}

variable "HEROKU_EMAIL" {
  description = "The heroku account's email address"
}

variable "HEROKU_API_KEY" {
  description = "An API key to the heroku account"
}

variable "app_name" {
  description = "Name of the Heroku app provisioned as an example"
}

provider "heroku" {
  email   = var.HEROKU_EMAIL
  api_key = var.HEROKU_API_KEY
}

resource "heroku_app" "app" {
  name   = var.app_name
  region = "us"
  stack  = "container"
}

resource "heroku_addon" "cache" {
  app  = var.app_name
  plan = "heroku-redis:hobby-dev"
  config = {
    maxmemory_policy = "allkeys-lru"
  }

  depends_on = [heroku_app.app]
}

resource "heroku_addon_attachment" "cache" {
  app_id   = var.app_name
  addon_id = heroku_addon.cache.id
  name     = "REDIS_CACHE"

  depends_on = [heroku_app.app]
}

# Build container & release to the app
resource "heroku_build" "app" {
  app = var.app_name

  source {
    path = "."
  }

  depends_on = [heroku_addon.cache]
}

resource "heroku_config" "app" {
    vars = {
        CURRENT_RELEASE_ID = heroku_build.app.release_id
    }

    sensitive_vars = {
    }

  depends_on = [heroku_build.app]
}

resource "heroku_app_config_association" "app" {
  app_id = heroku_app.app.id

  vars = heroku_config.app.vars
  sensitive_vars = heroku_config.app.sensitive_vars

  depends_on = [heroku_config.app]
}

resource "heroku_formation" "app" {
  app      = var.app_name
  type     = "web"
  quantity = 1
  size     = "Free"

  depends_on = [heroku_build.app]
}

resource "heroku_app_feature" "log_runtime_metrics" {
  app  = var.app_name
  name = "log-runtime-metrics"

  depends_on = [heroku_formation.app]
}

output "app_url" {
  value = "https://${var.app_name}.herokuapp.com"
}
