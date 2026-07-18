// Built-in template library — static, not tied to any org. Applying one
// clones it into the caller's org. Never assigns a responsible person /
// checklist assignee here; that's left for the owner to fill in afterwards.

export type FieldTemplate = {
  label: string;
  type: 'TEXT' | 'NUMBER' | 'DROPDOWN' | 'DATE' | 'PHOTO' | 'YESNO';
  required?: boolean;
  options?: string;
};

export type StageTemplate = {
  name: string;
  plannedMins?: number; // omitted = unplanned, no deadline, never "stuck"
  fields?: FieldTemplate[];
};

export type FmsTemplate = {
  id: string;
  type: 'FMS';
  name: string;
  description: string;
  prefix: string;
  itemLabel: string;
  stages: StageTemplate[];
};

export type ChecklistTemplate = {
  id: string;
  type: 'CHECKLIST';
  name: string;
  description: string;
  title: string;
  recurrence: 'DAILY' | 'WEEKLY' | 'MONTHLY';
  timeOfDay: string;
  weekday?: number;
  dayOfMonth?: number;
  priority: 'HIGH' | 'NORMAL' | 'LOW';
};

export type Template = FmsTemplate | ChecklistTemplate;

export const TEMPLATES: Template[] = [
  {
    id: 'fms-packaging',
    type: 'FMS',
    name: 'Packaging',
    description: 'Cutting → Printing → Dispatch',
    prefix: 'PKG',
    itemLabel: 'Batch',
    stages: [
      { name: 'Cutting', plannedMins: 60, fields: [
        { label: 'Quantity', type: 'NUMBER', required: true },
      ] },
      { name: 'Printing', plannedMins: 90, fields: [
        { label: 'Design approved', type: 'YESNO' },
      ] },
      { name: 'Dispatch', plannedMins: 30, fields: [
        { label: 'Tracking ID', type: 'TEXT' },
      ] },
    ],
  },
  {
    id: 'fms-order-to-delivery',
    type: 'FMS',
    name: 'Order to Delivery',
    description: 'Order received (unplanned) → Quotation → Production → Dispatch',
    prefix: 'ORD',
    itemLabel: 'Order',
    stages: [
      { name: 'Order received', fields: [
        { label: 'Customer name', type: 'TEXT', required: true },
      ] }, // no plannedMins — unplanned, no deadline, never "stuck"
      { name: 'Quotation', plannedMins: 240, fields: [
        { label: 'Quoted amount', type: 'NUMBER' },
      ] },
      { name: 'Production', plannedMins: 1440, fields: [
        { label: 'QC passed', type: 'YESNO' },
      ] },
      { name: 'Dispatch', plannedMins: 60, fields: [
        { label: 'Tracking ID', type: 'TEXT' },
      ] },
    ],
  },
  {
    id: 'fms-manufacturing-batch',
    type: 'FMS',
    name: 'Manufacturing Batch',
    description: 'Raw material check → Production → Quality check → Packing → Dispatch',
    prefix: 'MFG',
    itemLabel: 'Batch',
    stages: [
      { name: 'Raw material check', plannedMins: 30, fields: [
        { label: 'Materials available', type: 'YESNO' },
      ] },
      { name: 'Production', plannedMins: 480 },
      { name: 'Quality check', plannedMins: 60, fields: [
        { label: 'Defects found', type: 'NUMBER' },
        { label: 'Passed', type: 'YESNO' },
      ] },
      { name: 'Packing', plannedMins: 45 },
      { name: 'Dispatch', plannedMins: 30, fields: [
        { label: 'Tracking ID', type: 'TEXT' },
      ] },
    ],
  },
  {
    id: 'checklist-daily-opening',
    type: 'CHECKLIST',
    name: 'Daily Opening Checklist',
    description: 'Shop-floor opening checks — lights, safety gear, machine startup.',
    title: 'Daily opening checklist',
    recurrence: 'DAILY',
    timeOfDay: '09:00',
    priority: 'NORMAL',
  },
  {
    id: 'checklist-weekly-safety',
    type: 'CHECKLIST',
    name: 'Weekly Safety Check',
    description: 'Fire extinguishers, first aid kit, emergency exits, PPE stock.',
    title: 'Weekly safety check',
    recurrence: 'WEEKLY',
    timeOfDay: '09:30',
    weekday: 1,
    priority: 'HIGH',
  },
];
