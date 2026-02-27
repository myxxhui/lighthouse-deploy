-- [Ref: 01_设计 §产品分类 product_category_mapping 预置范围] 阿里云常见 ProductCode 预置，与 aliyun client productCodeToDomain 对齐；方案 B 下 drilldown 键前缀优先，本表兜底；执行时机：init 或首次部署后一次性执行。
-- 用法：psql $DATABASE_URL -f scripts/seed-product-category-mapping.sql
INSERT INTO product_category_mapping (product_code, category) VALUES
  ('ECS', 'compute'), ('ACK', 'compute'), ('CS', 'compute'), ('ecs_workflow', 'compute'),
  ('OSS', 'storage'), ('NAS', 'storage'), ('DISK', 'storage'),
  ('CDN', 'network'), ('SLB', 'network'), ('VPC', 'network'), ('EIP', 'network'),
  ('CDT', 'other'), ('SFM', 'other')
ON CONFLICT (product_code) DO NOTHING;
