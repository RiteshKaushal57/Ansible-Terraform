resource "aws_alb" "alb" {
  name            = "${var.environment}-alb"
  internal        = false
  load_balancer_type = "application"
  security_groups = [var.alb_sg_id]
  subnets         = var.subnets
}

resource "aws_alb_target_group" "web_servers" {
  name     = "${var.environment}-web-servers"
  port     = 5000      
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    path                = "/health"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
  }
}

resource "aws_alb_target_group_attachment" "web_servers" {
  count            = length(var.web_server_ids)
  target_group_arn = aws_alb_target_group.web_servers.arn
  target_id        = var.web_server_ids[count.index]
  port             = 5000    
}

resource "aws_alb_listener" "http" {
  load_balancer_arn = aws_alb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_alb_target_group.web_servers.arn
  }
}

