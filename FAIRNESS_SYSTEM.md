# ⚖️ نظام العدالة - ضمان عدم ظلم الموظفين

## 🎯 المبدأ الأساسي
**"الشفافية + قابلية الاعتراض + التعويض عن الأخطاء = عدالة"**

---

## 📋 السياسات الإلزامية

### 1. Payroll Preview (معاينة الراتب قبل الدفع)

```typescript
// قبل تحويل الراتب بـ 3 أيام
function sendPayrollPreview(employeeId: string, month: string) {
  const calculation = calculateSalary(employeeId, month);
  
  const preview = {
    employeeName: calculation.employeeName,
    baseSalary: calculation.baseSalary,
    
    // تفصيل الساعات
    totalWorkHours: calculation.totalWorkHours,
    requiredHours: 160,
    overtimeHours: calculation.overtimeHours,
    
    // الإضافات
    overtimeAmount: calculation.overtimeAmount,
    bonuses: calculation.bonuses,
    
    // الخصومات
    advances: calculation.advances,
    lateDeductions: calculation.lateDeductions,
    absenceDeductions: calculation.absenceDeductions,
    otherDeductions: calculation.otherDeductions,
    
    // الصافي
    grossSalary: calculation.grossSalary,
    totalDeductions: calculation.totalDeductions,
    netSalary: calculation.netSalary,
    
    // معلومات إضافية
    workDays: calculation.workDays,
    lateDays: calculation.lateDays,
    absentDays: calculation.absentDays,
    flaggedDays: calculation.flaggedDays, // أيام مشكوك فيها
    
    // حق الاعتراض
    appealDeadline: addDays(new Date(), 7),
    appealInstructions: 'اضغط "اعتراض" إذا وجدت خطأ'
  };
  
  // إرسال عبر App notification + Email + SMS
  sendNotification(employeeId, preview);
  
  return preview;
}
```

**كيف يظهر للموظف:**

```
╔════════════════════════════════════════╗
║   كشف الراتب - أكتوبر 2025            ║
╠════════════════════════════════════════╣
║ الراتب الأساسي:         6,000 جنيه   ║
║                                        ║
║ الإضافات:                             ║
║   ✅ ساعات إضافية (10h):  562.50     ║
║   ✅ بونص:                 200.00     ║
║                      ──────────────    ║
║   المجموع:                6,762.50    ║
║                                        ║
║ الخصومات:                             ║
║   ❌ سلفة:                 -500.00    ║
║   ❌ تأخير (3 أيام):      -45.00     ║
║   ❌ غياب (1 يوم):        -200.00    ║
║                      ──────────────    ║
║   المجموع:                -745.00     ║
║                                        ║
║ الصافي:                  6,017.50 جنيه║
║                                        ║
║ 📊 التفاصيل:                          ║
║   أيام العمل: 26 يوم                  ║
║   ساعات العمل: 170 ساعة               ║
║   أيام التأخير: 3                     ║
║   أيام الغياب: 1                      ║
║                                        ║
║ ⚠️  أيام تحتاج مراجعة: 2             ║
║   (14 أكتوبر، 21 أكتوبر)              ║
║                                        ║
║ [عرض التفاصيل] [اعتراض]               ║
║                                        ║
║ 📅 موعد الدفع: 5 نوفمبر 2025          ║
║ ⏰ آخر موعد للاعتراض: 12 نوفمبر       ║
╚════════════════════════════════════════╝
```

---

### 2. Grace Periods (فترات السماح)

```typescript
const GRACE_POLICIES = {
  // تأخير الحضور
  lateArrival: {
    gracePeriod: 10, // دقيقة
    firstOffense: 'warning',      // أول مرة: تحذير فقط
    secondOffense: 'partial',     // ثاني مرة: خصم 50%
    thirdOffense: 'full',         // ثالث مرة: خصم كامل
  },
  
  // نسيان Check-out
  forgotCheckout: {
    autoCheckoutTime: '22:00',    // Auto check-out ساعة 10 مساءً
    canAppeal: true,              // يمكن الاعتراض
    appealDeadline: 24,           // 24 ساعة
  },
  
  // فترة تجريبية لفرع جديد
  newBranch: {
    learningPeriod: 14,           // 14 يوم
    noDeductionsDuring: true,     // لا خصومات خلال التجربة
    onlyWarnings: true,           // تحذيرات فقط
  },
  
  // فترة تجريبية لموظف جديد
  newEmployee: {
    graceDays: 7,                 // 7 أيام
    reducedPenalties: 0.5,        // خصم 50% من العقوبة
  },
  
  // أعطال تقنية
  technicalIssue: {
    autoCompensate: true,         // تعويض تلقائي
    requiresProof: false,         // لا يحتاج دليل
    logIncident: true,            // تسجيل في audit log
  }
};
```

**مثال:**

```
موظف جديد (5 أيام في العمل):
- تأخر 15 دقيقة
- الخصم العادي: 15 × (37.5 ÷ 60) = 9.375 جنيه
- الخصم الفعلي: 9.375 × 0.5 = 4.69 جنيه (50% فقط)
- يظهر تنبيه: "⚠️ موظف جديد - خصم مخفض"
```

---

### 3. Appeal Flow (نظام الاعتراض)

```typescript
interface Appeal {
  id: string;
  employeeId: string;
  month: string;
  appealType: 'LATE' | 'ABSENT' | 'DEDUCTION' | 'HOURS' | 'OTHER';
  
  // تفاصيل الاعتراض
  disputedDate: Date;
  disputedAmount: number;
  employeeStatement: string;
  evidence: string[];  // صور، documents، إلخ
  
  // المراجعة
  reviewedBy: string;  // Manager/HR
  reviewedAt: Date;
  decision: 'APPROVED' | 'REJECTED' | 'PARTIAL';
  compensationAmount: number;
  hrNotes: string;
  
  // SLA
  submittedAt: Date;
  deadlineForReview: Date;  // 72 ساعة
  status: 'PENDING' | 'UNDER_REVIEW' | 'RESOLVED' | 'ESCALATED';
}

// إجراء الاعتراض
async function submitAppeal(appeal: Appeal) {
  // 1. حفظ الاعتراض
  await db.insert(appeals).values(appeal);
  
  // 2. إشعار المدير فوراً
  await sendNotification(appeal.managerId, {
    title: '🔔 اعتراض جديد',
    body: `${appeal.employeeName} اعترض على خصم ${appeal.disputedAmount} جنيه`,
    priority: 'HIGH'
  });
  
  // 3. تجميد الخصم مؤقتاً
  await freezeDeduction(appeal.deductionId);
  
  // 4. جدولة تصعيد تلقائي (لو مافيش رد خلال 72 ساعة)
  scheduleEscalation(appeal.id, 72);
  
  return appeal;
}

// مراجعة الاعتراض
async function reviewAppeal(
  appealId: string,
  decision: 'APPROVED' | 'REJECTED' | 'PARTIAL',
  notes: string,
  reviewerId: string
) {
  const appeal = await db.query.appeals.findFirst({
    where: eq(appeals.id, appealId)
  });
  
  let compensationAmount = 0;
  
  if (decision === 'APPROVED') {
    // موافقة كاملة → إلغاء الخصم
    compensationAmount = appeal.disputedAmount;
    await removeDeduction(appeal.deductionId);
    
  } else if (decision === 'PARTIAL') {
    // موافقة جزئية → تخفيض الخصم
    compensationAmount = appeal.disputedAmount * 0.5;
    await reduceDeduction(appeal.deductionId, 0.5);
  }
  
  // تحديث الاعتراض
  await db.update(appeals)
    .set({
      decision,
      compensationAmount,
      hrNotes: notes,
      reviewedBy: reviewerId,
      reviewedAt: new Date(),
      status: 'RESOLVED'
    })
    .where(eq(appeals.id, appealId));
  
  // إشعار الموظف
  await sendNotification(appeal.employeeId, {
    title: decision === 'APPROVED' ? '✅ تمت الموافقة' : '❌ تم الرفض',
    body: `اعتراضك على خصم ${appeal.disputedAmount} جنيه: ${decision}`,
    data: { compensationAmount, notes }
  });
  
  // Audit log
  await logAction('APPEAL_REVIEWED', {
    appealId,
    decision,
    reviewerId,
    compensationAmount
  });
}
```

**واجهة الموظف:**

```
╔════════════════════════════════════════╗
║   اعتراض على خصم                      ║
╠════════════════════════════════════════╣
║ التاريخ: 14 أكتوبر 2025                ║
║ الخصم: 200 جنيه (غياب)                ║
║                                        ║
║ السبب:                                ║
║ [✓] كنت موجوداً لكن المشكلة تقنية      ║
║ [ ] كان عندي عذر (مرفق شهادة)         ║
║ [ ] آخر                               ║
║                                        ║
║ التفاصيل:                             ║
║ ┌────────────────────────────────────┐ ║
║ │ الموبايل فصل البطارية ومقدرتش      │ ║
║ │ أعمل check-in. كنت في الشفت من    │ ║
║ │ 9 الصبح لـ 5 العصر.                │ ║
║ └────────────────────────────────────┘ ║
║                                        ║
║ الأدلة (اختياري):                     ║
║ [📷 إضافة صورة]  [📄 إضافة ملف]       ║
║                                        ║
║ [إرسال الاعتراض]                      ║
║                                        ║
║ ⏰ آخر موعد: 21 أكتوبر                ║
║ 📝 سيتم الرد خلال 72 ساعة             ║
╚════════════════════════════════════════╝
```

---

### 4. Transparent Flags (شفافية التنبيهات)

```typescript
// كل flag يُشرح للموظف بوضوح
const FLAG_EXPLANATIONS = {
  NO_MOTION: {
    ar: 'لم تُسجّل حركة لمدة {duration} دقيقة',
    suggestion: 'تحرك قليلاً أو اضغط زر التأكيد',
    severity: 'MEDIUM',
    autoResolve: false
  },
  
  WIFI_MISMATCH: {
    ar: 'شبكة WiFi مختلفة عن شبكة الفرع',
    suggestion: 'تأكد من الاتصال بشبكة {expectedSSID}',
    severity: 'HIGH',
    autoResolve: false
  },
  
  GPS_OUTSIDE_GEOFENCE: {
    ar: 'الموقع خارج نطاق الفرع ({distance}م)',
    suggestion: 'تأكد من وجودك داخل الفرع',
    severity: 'HIGH',
    autoResolve: false
  },
  
  HEARTBEAT_LOST: {
    ar: 'لم تصل نبضات منذ {duration} دقيقة',
    suggestion: 'تحقق من اتصال الإنترنت',
    severity: 'LOW',
    autoResolve: true
  },
  
  TRUST_SCORE_LOW: {
    ar: 'البيانات البيئية غير مطابقة ({score}%)',
    suggestion: 'قد يكون هناك خلل تقني، سنراجع يدوياً',
    severity: 'MEDIUM',
    autoResolve: false
  },
  
  DEVICE_BLACKLISTED: {
    ar: 'هذا الجهاز محظور من النظام',
    suggestion: 'تواصل مع HR',
    severity: 'CRITICAL',
    autoResolve: false
  }
};

// إرسال إشعار واضح للموظف
async function notifyEmployeeOfFlag(flag: PulseFlag) {
  const explanation = FLAG_EXPLANATIONS[flag.type];
  
  await sendNotification(flag.employeeId, {
    title: `⚠️ ${explanation.ar}`,
    body: explanation.suggestion,
    data: {
      flagId: flag.id,
      severity: explanation.severity,
      canAppeal: true,
      appealInstructions: 'يمكنك تقديم اعتراض من صفحة الحضور'
    }
  });
}
```

---

### 5. Compensation on False Positive (التعويض عن الأخطاء)

```typescript
// إذا ثبت أن النظام أخطأ
async function compensateFalsePositive(
  employeeId: string,
  deductionId: string,
  reason: string
) {
  const deduction = await db.query.deductions.findFirst({
    where: eq(deductions.id, deductionId)
  });
  
  // 1. إلغاء الخصم
  await db.update(deductions)
    .set({ 
      status: 'CANCELLED',
      cancellationReason: reason,
      cancelledAt: new Date()
    })
    .where(eq(deductions.id, deductionId));
  
  // 2. إضافة تعويض
  await db.insert(compensations).values({
    id: uuidv4(),
    employeeId,
    amount: deduction.amount,
    reason: `تعويض عن خطأ نظام: ${reason}`,
    approvedBy: 'SYSTEM',
    status: 'APPROVED',
    paidAt: new Date()
  });
  
  // 3. إشعار الموظف + اعتذار
  await sendNotification(employeeId, {
    title: '✅ تم التعويض',
    body: `نعتذر عن الخطأ. تم إضافة ${deduction.amount} جنيه لراتبك القادم`,
    tone: 'APOLOGETIC'
  });
  
  // 4. Audit log
  await logAction('FALSE_POSITIVE_COMPENSATED', {
    employeeId,
    deductionId,
    amount: deduction.amount,
    reason
  });
  
  // 5. تحديث device/branch calibration (لتجنب تكرار الخطأ)
  await recalibrateBranchBaseline(deduction.branchId);
  
  return { compensated: true, amount: deduction.amount };
}
```

---

### 6. Graduated Penalties (تدرج العقوبة)

```typescript
// نظام العقوبات المتدرج (لا خصم فوري)
const PENALTY_SYSTEM = {
  LATE_ARRIVAL: [
    { occurrence: 1, action: 'WARNING', deduction: 0 },
    { occurrence: 2, action: 'WARNING', deduction: 0 },
    { occurrence: 3, action: 'PARTIAL_DEDUCTION', deduction: 0.5 },
    { occurrence: 4, action: 'FULL_DEDUCTION', deduction: 1.0 },
    { occurrence: 5, action: 'ESCALATE_TO_HR', deduction: 1.0 }
  ],
  
  NO_MOTION: [
    { occurrence: 1, action: 'REMINDER', deduction: 0 },
    { occurrence: 2, action: 'WARNING', deduction: 0 },
    { occurrence: 3, action: 'MANAGER_REVIEW', deduction: 0 },
    { occurrence: 4, action: 'DEDUCTION', deduction: 0.25 }
  ],
  
  FORGOT_CHECKOUT: [
    { occurrence: 1, action: 'AUTO_FIX', deduction: 0 },
    { occurrence: 2, action: 'WARNING', deduction: 0 },
    { occurrence: 3, action: 'PARTIAL_DEDUCTION', deduction: 0.3 }
  ]
};

// تطبيق العقوبة المناسبة
async function applyGraduatedPenalty(
  employeeId: string,
  violationType: string,
  amount: number
) {
  // عدد المرات السابقة في آخر 30 يوم
  const recentViolations = await db.select()
    .from(violations)
    .where(and(
      eq(violations.employeeId, employeeId),
      eq(violations.type, violationType),
      gte(violations.createdAt, subDays(new Date(), 30))
    ));
  
  const occurrenceCount = recentViolations.length + 1;
  const penalty = PENALTY_SYSTEM[violationType].find(
    p => p.occurrence === occurrenceCount
  ) || PENALTY_SYSTEM[violationType].slice(-1)[0]; // آخر عقوبة
  
  let finalAmount = amount * penalty.deduction;
  
  // تسجيل المخالفة
  await db.insert(violations).values({
    id: uuidv4(),
    employeeId,
    type: violationType,
    occurrence: occurrenceCount,
    action: penalty.action,
    originalAmount: amount,
    deductedAmount: finalAmount,
    createdAt: new Date()
  });
  
  // إشعار الموظف
  const message = {
    WARNING: `⚠️ تحذير (${occurrenceCount}/3): ${violationType}`,
    PARTIAL_DEDUCTION: `⚠️ خصم جزئي (${finalAmount} جنيه)`,
    FULL_DEDUCTION: `❌ خصم كامل (${finalAmount} جنيه)`,
    ESCALATE_TO_HR: `🚨 تصعيد للـ HR - تكرار المخالفة`
  };
  
  await sendNotification(employeeId, {
    title: message[penalty.action],
    body: `المخالفة: ${violationType} - المرة ${occurrenceCount}`
  });
  
  return { action: penalty.action, amount: finalAmount };
}
```

---

### 7. Audit Trail كامل

```typescript
// كل تعديل يُسجّل
async function logManualOverride(
  action: string,
  performedBy: string,
  details: any
) {
  await db.insert(auditLogs).values({
    id: uuidv4(),
    action,
    performedBy,
    performedAt: new Date(),
    details: JSON.stringify(details),
    ipAddress: req.ip,
    userAgent: req.headers['user-agent']
  });
}

// أمثلة:
await logManualOverride('DEDUCTION_CANCELLED', 'manager-123', {
  employeeId: 'emp-456',
  deductionId: 'ded-789',
  originalAmount: 200,
  reason: 'False positive - technical issue'
});

await logManualOverride('SALARY_ADJUSTED', 'hr-999', {
  employeeId: 'emp-456',
  month: '2025-10',
  adjustment: +500,
  reason: 'Compensation for system error'
});
```

---

## 📊 Dashboard للشفافية

### للموظف:

```
╔════════════════════════════════════════╗
║   سجل الحضور - أكتوبر 2025            ║
╠════════════════════════════════════════╣
║ 📅 1 أكتوبر:                          ║
║   ✅ 09:05 - 17:30 (8h 25m)           ║
║   الحالة: عادي                        ║
║                                        ║
║ 📅 2 أكتوبر:                          ║
║   ⚠️  09:18 - 17:15 (7h 57m)          ║
║   الحالة: تأخير 18 دقيقة             ║
║   الخصم: 0 (تحذير أول)                ║
║   [تفاصيل] [اعتراض]                  ║
║                                        ║
║ 📅 3 أكتوبر:                          ║
║   ❌ غائب                             ║
║   الخصم: 200 جنيه                     ║
║   الحالة: قيد المراجعة                ║
║   [اعتراض مُقدّم - ينتظر الرد]        ║
║                                        ║
║ 📅 14 أكتوبر:                         ║
║   🔍 09:00 - 17:00 (8h 0m)            ║
║   Flag: NO_MOTION (12:00-14:00)       ║
║   الحالة: يحتاج توضيح                 ║
║   [شرح الحالة]                        ║
║                                        ║
║ الإحصائيات:                           ║
║   ✅ أيام حضور: 24                    ║
║   ⚠️  أيام تأخير: 3                  ║
║   ❌ أيام غياب: 1                     ║
║   🔍 أيام مراجعة: 2                   ║
╚════════════════════════════════════════╝
```

### للمدير:

```
╔════════════════════════════════════════╗
║   قائمة الاعتراضات                    ║
╠════════════════════════════════════════╣
║ 🔴 عاجل (تأخير > 48 ساعة):           ║
║                                        ║
║ 1. أحمد محمد - غياب 14 أكتوبر        ║
║    الخصم: 200 جنيه                    ║
║    السبب: "مشكلة تقنية"               ║
║    الأدلة: 1 صورة                     ║
║    [مراجعة] [موافقة] [رفض]            ║
║                                        ║
║ ⚠️  متوسط الأولوية:                  ║
║                                        ║
║ 2. سارة علي - تأخير 20 دقيقة         ║
║    الخصم: 12.5 جنيه                   ║
║    السبب: "زحمة"                      ║
║    [مراجعة]                           ║
║                                        ║
║ 3. محمود حسن - NO_MOTION flag        ║
║    الخصم: 0 (flag فقط)                ║
║    السبب: "كنت في المخزن"             ║
║    [مراجعة]                           ║
╚════════════════════════════════════════╝
```

---

## ✅ Checklist العدالة

نظام يُعتبر "حقاني" إذا:

- [x] يرسل Payroll Preview قبل 3 أيام من الدفع
- [x] يوفر Grace Period (10 دقائق تأخير)
- [x] يستخدم Graduated Penalties (تحذير قبل الخصم)
- [x] يسمح بالاعتراض خلال 7 أيام
- [x] يرد على الاعتراض خلال 72 ساعة
- [x] يوضح سبب كل flag للموظف
- [x] يعوّض عن الأخطاء التقنية
- [x] يسجل كل تعديل في Audit Log
- [x] يوفر شفافية كاملة في الحسابات
- [x] يعطي فترة تجريبية للفروع/الموظفين الجدد

---

## 🎯 الخلاصة

**النظام عادل إذا:**
1. الموظف يعرف راتبه **قبل** ما يتحول
2. الموظف يقدر **يعترض** على أي خصم
3. الأخطاء التقنية **تتعوّض** تلقائياً
4. كل شيء **موثّق** و**شفاف**
5. العقوبة **متدرجة** مش فورية

**= نظام حقاني ✅**
