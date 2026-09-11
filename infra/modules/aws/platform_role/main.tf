resource "aws_iam_role" "this" {
  name               = "${var.base_name}-ec2"
  assume_role_policy = data.aws_iam_policy_document.instance_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "platform" {
  name   = "${var.base_name}-ec2"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.platform.json
}

resource "aws_iam_instance_profile" "this" {
  name = "${var.base_name}-ec2"
  role = aws_iam_role.this.name
}
