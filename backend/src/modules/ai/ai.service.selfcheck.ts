// Assert-based self-check for normalizeFlowStageSuggestions — the FMS
// planned-time rule (first stage unplanned, every later stage planned) must
// hold regardless of what the model returns. No DB, no framework, no
// network: `npx tsx src/modules/ai/ai.service.selfcheck.ts`.
import assert from 'node:assert';
import { normalizeFlowStageSuggestions } from './ai.service';

function main() {
  // Model followed the rule already — passes through unchanged.
  {
    const stages = normalizeFlowStageSuggestions([
      { name: 'Order received', plannedMins: null, fields: [] },
      { name: 'Packaging', plannedMins: 45, fields: [{ label: 'Box size', type: 'TEXT', required: false }] },
      { name: 'Dispatch', plannedMins: 30 },
    ]);
    assert.strictEqual(stages.length, 3);
    assert.strictEqual(stages[0]!.plannedMins, null, 'first stage must stay unplanned');
    assert.strictEqual(stages[1]!.plannedMins, 45, 'later stage keeps its suggested duration');
    assert.strictEqual(stages[2]!.plannedMins, 30);
  }

  // Model broke the rule both ways — first stage got a number, a later stage
  // got null — normalization must correct both.
  {
    const stages = normalizeFlowStageSuggestions([
      { name: 'Order received', plannedMins: 20 },
      { name: 'QC', plannedMins: null },
      { name: 'Dispatch', plannedMins: 15 },
    ]);
    assert.strictEqual(stages[0]!.plannedMins, null, 'first stage must be forced to unplanned even if the model gave it a number');
    assert.strictEqual(stages[1]!.plannedMins, 60, 'a later stage missing a duration must get a fallback, never null');
    assert.strictEqual(stages[2]!.plannedMins, 15);
  }

  // Junk items (no name, wrong shapes) are dropped; a valid field's type
  // alias is normalized; an unrecognized field type is dropped.
  {
    const stages = normalizeFlowStageSuggestions([
      { name: '  ' }, // blank name, dropped
      'not an object', // dropped
      {
        name: 'Cutting',
        plannedMins: 90,
        fields: [
          { label: 'Color', type: 'select', options: ['Red', 'Blue'] },
          { label: 'Bad field', type: 'NOT_A_TYPE' },
          { label: '', type: 'TEXT' }, // blank label, dropped
        ],
      },
    ]);
    assert.strictEqual(stages.length, 1, 'blank-name and non-object items must be dropped');
    assert.strictEqual(stages[0]!.plannedMins, null, 'the one surviving stage is first, so still forced unplanned');
    assert.strictEqual(stages[0]!.fields.length, 1, 'only the one valid field survives');
    assert.strictEqual(stages[0]!.fields[0]!.type, 'DROPDOWN', 'type alias "select" normalizes to DROPDOWN');
    assert.strictEqual(stages[0]!.fields[0]!.options, 'Red,Blue');
  }

  console.log('ai.service (flow-stage suggestions) self-check: all assertions passed');
}

main();
