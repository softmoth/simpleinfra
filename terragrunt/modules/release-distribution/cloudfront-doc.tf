module "lambda_doc_router" {
  source = "../aws-lambda"
  providers = {
    aws = aws.east1
  }

  name       = "${local.name}--doc-router"
  source_dir = "lambdas/doc-router"
  handler    = "index.handler"
  runtime    = "nodejs20.x"
  role_arn   = data.aws_iam_role.cloudfront_lambda.arn
}

resource "aws_cloudfront_response_headers_policy" "cache_immutable" {
  name = format("immutable-for-%s-releases", var.environment)

  custom_headers_config {
    items {
      header   = "Cache-Control"
      override = true
      value = format(
        "immutable, max-age=%d, stale-while-revalidate=%d",
        data.aws_cloudfront_cache_policy.caching.default_ttl,
        data.aws_cloudfront_cache_policy.caching.default_ttl,
      )
    }
  }
}

data "aws_cloudfront_cache_policy" "caching" {
  name = "Managed-CachingOptimized"
}

resource "aws_cloudfront_distribution" "doc" {
  comment = var.doc_domain_name

  enabled             = true
  http_version        = "http2and3"
  wait_for_deployment = false
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  price_class         = "PriceClass_All"

  aliases = [var.doc_domain_name]
  viewer_certificate {
    acm_certificate_arn      = module.certificate.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.1_2016"
  }

  default_cache_behavior {
    target_origin_id       = "main"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      headers      = []
      query_string = false
      cookies {
        forward = "none"
      }
    }

    lambda_function_association {
      event_type   = "origin-request"
      lambda_arn   = module.lambda_doc_router.version_arn
      include_body = false
    }
  }

  ordered_cache_behavior {
    path_pattern     = "*.woff2"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = "main"

    response_headers_policy_id = aws_cloudfront_response_headers_policy.cache_immutable.id
    cache_policy_id            = data.aws_cloudfront_cache_policy.caching.id

    compress               = true
    viewer_protocol_policy = "redirect-to-https"

    lambda_function_association {
      event_type   = "origin-request"
      lambda_arn   = module.lambda_doc_router.version_arn
      include_body = false
    }
  }

  origin {
    origin_id   = "main"
    domain_name = data.aws_s3_bucket.static.website_endpoint
    origin_path = "/doc"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
}

data "aws_route53_zone" "doc" {
  // Convert foo.bar.baz into bar.baz
  name = join(".", reverse(slice(reverse(split(".", var.doc_domain_name)), 0, 2)))
}

resource "aws_route53_record" "doc_ipv4" {
  zone_id = data.aws_route53_zone.doc.id
  name    = var.doc_domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.doc.domain_name
    zone_id                = aws_cloudfront_distribution.doc.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "doc_ipv6" {
  zone_id = data.aws_route53_zone.doc.id
  name    = var.doc_domain_name
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.doc.domain_name
    zone_id                = aws_cloudfront_distribution.doc.hosted_zone_id
    evaluate_target_health = false
  }
}
