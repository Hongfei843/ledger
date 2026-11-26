import os, re

ROOT = r'D:\开发\记账App'
SRC = os.path.join(ROOT, 'Ledger', 'Data', 'Models')
OUT = os.path.join(ROOT, 'Ledger', 'Domain', 'Backup', 'BackupDTOs.swift')

MODELS = [
    ('Book.swift', 'Book'),
    ('Account.swift', 'Account'),
    ('Category.swift', 'Category'),
    ('Txn.swift', 'Txn'),
    ('Claim.swift', 'Claim'),
    ('Loan.swift', 'Loan'),
    ('LoanScheduleItem.swift', 'LoanScheduleItem'),
    ('Statement.swift', 'Statement'),
    ('ReconciliationRun.swift', 'ReconciliationRun'),
    ('Debt.swift', 'Debt'),
    ('MerchantRule.swift', 'MerchantRule'),
    ('CaptureRecord.swift', 'CaptureRecord'),
    ('RecurringRule.swift', 'RecurringRule'),
    ('QuickTemplate.swift', 'QuickTemplate'),
]

ALLOWED = {'UUID', 'String', 'Int64', 'Int', 'Double', 'Bool', 'Date'}
prop_re = re.compile(r'^(?:@Attribute\([^)]*\)\s+)?var\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*([A-Za-z0-9_]+)(\?)?\s*$')


def parse_fields(path, class_name):
    lines = open(path, encoding='utf-8').read().split('\n')
    # 定位 final class
    start = None
    for i, line in enumerate(lines):
        if re.match(rf'\s*(?:@Model\s*)?final class {class_name}\b', line) or re.match(rf'final class {class_name}\b', line.strip()):
            start = i
            break
    if start is None:
        raise SystemExit(f'class not found: {class_name} in {path}')
    fields = []
    for line in lines[start + 1:]:
        if re.match(r'\s+init\(', line):
            break
        m = prop_re.match(line.strip())
        if not m:
            continue
        name, base, opt = m.group(1), m.group(2), m.group(3)
        if base not in ALLOWED:
            continue
        fields.append((name, base + ('?' if opt else '')))
    if not fields:
        raise SystemExit(f'no fields for {class_name}')
    return fields


out = []
out.append('// 由 scripts/gen-backup-dtos.py 自动生成，勿手改。')
out.append('// 修改模型字段后，重新运行脚本生成。')
out.append('import Foundation')
out.append('')
for filename, cls in MODELS:
    fields = parse_fields(os.path.join(SRC, filename), cls)
    dto = f'{cls}DTO'
    out.append(f'struct {dto}: Codable {{')
    for name, t in fields:
        out.append(f'    var {name}: {t}')
    out.append('}')
    out.append('')
    out.append(f'extension {dto} {{')
    out.append(f'    init(_ model: {cls}) {{')
    for name, _ in fields:
        out.append(f'        self.{name} = model.{name}')
    out.append('    }')
    out.append('')
    out.append(f'    func apply(to model: {cls}) {{')
    for name, _ in fields:
        out.append(f'        model.{name} = {name}')
    out.append('    }')
    out.append('}')
    out.append('')

os.makedirs(os.path.dirname(OUT), exist_ok=True)
open(OUT, 'w', encoding='utf-8').write('\n'.join(out))
print('wrote', OUT, 'lines:', len(out))
for filename, cls in MODELS:
    print(cls, 'fields=', len(parse_fields(os.path.join(SRC, filename), cls)))
