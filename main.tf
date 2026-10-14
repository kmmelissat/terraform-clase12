terraform {
  required_version = ">= 1.9"
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "4.5.0"
    }
  }
}

provider "docker" {}

resource "docker_image" "web" {
  name         = "nginx:alpine"
  keep_locally = true
}

resource "docker_container" "web" {
  name        = "tf-web"
  image       = docker_image.web.image_id
  memory      = 256
  memory_swap = 512

  ports {
    internal = 80
    external = 8081
  }
}
