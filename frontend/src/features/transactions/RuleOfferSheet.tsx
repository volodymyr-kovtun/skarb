import { useEffect, useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { Check, RotateCcw } from 'lucide-react'
import {
  api, refreshAll, type Category, type RuleApplied, type RuleMatchCounts, type RuleScope,
  type RuleSuggestion, type Tx,
} from '../../shared/api'
import { Modal, TxRow, btnGhost, btnPrimary, errMsg, fieldLabelCls } from '../../shared/ui'

/** Long enough to read the count and reach for Undo, short enough not to linger. */
const TOAST_MS = 9000
/** Typing a keyword shouldn't fire a count request per keystroke. */
const DEBOUNCE_MS = 300

/**
 * Offered after a category is changed by hand: turn that one correction into a keyword rule that
 * files the matching transactions you already have, and every one that arrives from now on.
 *
 * It opens *after* the save has landed, so closing it costs nothing — the transaction stays
 * corrected either way. The keyword is editable and the counts under it are recomputed by the
 * server as it changes, so the guess never has to be right, only correctable.
 */
export function RuleOfferSheet({ tx, category, initial, onClose }:
  { tx: Tx; category: Category; initial: RuleSuggestion; onClose: () => void }) {
  const qc = useQueryClient()
  const initialPattern = initial.pattern ?? ''
  const [pattern, setPattern] = useState(initialPattern)
  const [debounced, setDebounced] = useState(initialPattern)
  const [applyPast, setApplyPast] = useState(true)
  const [includeUntouched, setIncludeUntouched] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  // Captured at save time, not read back from the query: saving invalidates the suggestion, and
  // the refetched view no longer mentions the rule that was just created or repointed.
  const [done, setDone] = useState<{ result: RuleApplied; previous: RuleSuggestion['existingRule'] } | null>(null)

  useEffect(() => {
    const t = setTimeout(() => setDebounced(pattern.trim()), DEBOUNCE_MS)
    return () => clearTimeout(t)
  }, [pattern])

  const { data, isFetching } = useQuery({
    queryKey: ['rule-suggestion', tx.id, debounced],
    queryFn: () => api.ruleSuggestion(tx.id, debounced),
    // The opening view was already fetched to decide whether to offer at all — don't ask twice.
    initialData: debounced === initialPattern ? initial : undefined,
    // Keep the previous counts on screen while the next ones load, so editing the keyword
    // never blanks the sheet out from under the cursor.
    placeholderData: (prev) => prev,
  })
  const view = data ?? initial

  const counts = view.matches
  const automatic = counts.uncategorized + counts.automatic
  const scope: RuleScope = !applyPast ? 'none' : includeUntouched ? 'all' : 'automatic'
  const matched = automatic + counts.untouched
  // What the checkbox would actually rewrite — hand-sorted rows are held back until asked for.
  const changing = includeUntouched ? matched : automatic
  const existing = view.existingRule
  const ready = pattern.trim().length > 0

  const save = async () => {
    setBusy(true)
    setError('')
    try {
      const keyword = pattern.trim()
      const result = existing
        ? await api.updateRule(existing.id, { categoryId: category.id, pattern: keyword, applyTo: scope })
        : await api.createRule({ pattern: keyword, categoryId: category.id, applyTo: scope })
      refreshAll(qc)
      setDone({ result, previous: existing })
    } catch (e) {
      setError(errMsg(e))
    } finally {
      setBusy(false)
    }
  }

  const undo = async () => {
    if (!done) return
    const { result, previous } = done
    try {
      // Put the rule back where it was — repointed if it already existed, deleted if this
      // created it — and then restore every category this run rewrote.
      if (previous) await api.updateRule(previous.id, { categoryId: previous.category.id, applyTo: 'none' })
      else await api.deleteRule(result.id)
      if (result.reverts.length) await api.revertRules(result.reverts)
      refreshAll(qc)
    } finally {
      onClose()
    }
  }

  if (done) return <SavedToast applied={done.result.applied} onUndo={undo} onClose={onClose} />

  return (
    <Modal
      title={existing
        ? `Point “${existing.pattern}” at ${category.emoji} ${category.name} instead?`
        : `Always file this as ${category.emoji} ${category.name}?`}
      onClose={onClose}
    >
      <div className="flex flex-col gap-3">
        {existing ? (
          <p className="rounded-row bg-surface2 px-4 py-3 text-[13px] leading-relaxed text-muted">
            A rule already sends <b className="font-semibold text-ink">{existing.pattern}</b> to{' '}
            {existing.category.emoji} {existing.category.name}. Changing it keeps one rule instead of
            two that disagree.
          </p>
        ) : (
          <p className="-mt-1 text-[13px] text-muted">
            Skarb will use this keyword on new transactions as they arrive.
          </p>
        )}

        <div>
          <span className={fieldLabelCls}>Keyword</span>
          <label className="flex items-center gap-3 rounded-row bg-surface2 px-4 py-2.5 transition-shadow focus-within:shadow-[inset_0_0_0_1.5px_var(--sk-accent)]">
            <input
              className="w-full min-w-0 bg-transparent font-mono text-[13px] font-semibold text-ink outline-none placeholder:font-sans placeholder:font-normal placeholder:text-faint"
              value={pattern}
              onChange={(e) => setPattern(e.target.value)}
              placeholder="Which word identifies this merchant?"
              autoFocus
            />
            <span className="tnum shrink-0 text-xs text-faint">
              {isFetching || debounced !== pattern.trim()
                ? 'counting…'
                : `${matched} match${matched === 1 ? '' : 'es'}`}
            </span>
          </label>
          {view.alternatives.length > 0 && (
            <div className="mt-2 flex flex-wrap gap-1.5">
              {view.alternatives.map((alt) => (
                <button
                  key={alt}
                  onClick={() => setPattern(alt)}
                  className="rounded-full bg-surface2 px-3 py-1.5 font-mono text-[11.5px] font-semibold text-muted transition-colors hover:text-ink"
                >
                  {alt}
                </button>
              ))}
            </div>
          )}
        </div>

        {view.sample.length > 0 && (
          <div className="border-t border-line pt-1.5">
            {view.sample.map((s) => <TxRow key={s.id} tx={s} />)}
            {matched > view.sample.length && (
              <p className="px-3 pt-1 text-[12.5px] text-faint">
                and {matched - view.sample.length} more
              </p>
            )}
          </div>
        )}

        {matched > 0 && (
          <label className="flex items-start gap-2.5 text-sm">
            <input
              type="checkbox"
              checked={applyPast}
              onChange={(e) => setApplyPast(e.target.checked)}
              className="mt-0.5 h-4 w-4 shrink-0 accent-[var(--sk-accent)]"
            />
            <span>
              <span className="font-semibold">Also file the {changing} I already have</span>
              <span className="mt-0.5 block text-[12.5px] leading-relaxed text-faint">
                <Breakdown counts={counts} includeUntouched={includeUntouched} />
                {counts.untouched > 0 && (
                  <>
                    {' '}
                    <button
                      onClick={(e) => { e.preventDefault(); setIncludeUntouched(!includeUntouched) }}
                      className="font-semibold text-accent hover:underline"
                    >
                      {includeUntouched ? 'leave those alone' : 'include those too'}
                    </button>.
                  </>
                )}
              </span>
            </span>
          </label>
        )}

        {error && <p className="text-sm text-danger">{error}</p>}

        <div className="mt-2 flex justify-end gap-2">
          <button className={btnGhost} onClick={onClose}>
            {existing ? 'Keep both rules' : 'Not now'}
          </button>
          <button className={btnPrimary} onClick={save} disabled={busy || !ready}>
            {busy ? 'Saving…' : existing ? 'Update rule' : 'Create rule'}
          </button>
        </div>
      </div>
    </Modal>
  )
}

/** Says which of the matches are guesses and which are decisions, so neither is a surprise. */
function Breakdown({ counts, includeUntouched }:
  { counts: RuleMatchCounts; includeUntouched: boolean }) {
  const parts: string[] = []
  if (counts.uncategorized > 0) parts.push(`${counts.uncategorized} uncategorized`)
  if (counts.automatic > 0) parts.push(`${counts.automatic} filed automatically`)
  const lead = parts.length > 0 ? `${parts.join(', ')}.` : ''
  if (counts.untouched === 0) return <>{lead}</>

  const them = counts.untouched === 1 ? 'it is' : 'they are'
  return (
    <>
      {lead}{lead && ' '}
      {counts.untouched} you sorted by hand{' '}
      {includeUntouched ? 'will be re-filed too' : `stay as ${them}`} —
    </>
  )
}

/**
 * Rewriting a pile of transactions on one click needs a way back. The apply already returned every
 * row it touched and what it was filed as before, so undo is that list handed straight back.
 */
function SavedToast({ applied, onUndo, onClose }:
  { applied: number; onUndo: () => void; onClose: () => void }) {
  useEffect(() => {
    const t = setTimeout(onClose, TOAST_MS)
    return () => clearTimeout(t)
  }, [onClose])

  return (
    <div className="fixed inset-x-0 bottom-8 z-50 flex justify-center px-6" role="status">
      <div className="flex items-center gap-3 rounded-full bg-surface px-5 py-3 text-sm font-semibold shadow-pop">
        <Check size={17} className="shrink-0 text-income" />
        <span>
          Rule saved
          {applied > 0 && ` · ${applied} transaction${applied === 1 ? '' : 's'} re-filed`}
        </span>
        <button onClick={onUndo} className="ml-1 flex items-center gap-1.5 font-semibold text-accent hover:underline">
          <RotateCcw size={14} />
          Undo
        </button>
      </div>
    </div>
  )
}
