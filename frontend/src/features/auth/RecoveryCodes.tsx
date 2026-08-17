import { useState } from 'react'
import { Check, Copy, Download } from 'lucide-react'
import { btnGhost } from '../../shared/ui'

/**
 * Shown exactly once, at the moment the codes are issued — the server only keeps hashes,
 * so there is no second chance to read them.
 */
export function RecoveryCodes({ codes }: { codes: string[] }) {
  const [copied, setCopied] = useState(false)
  const asText = codes.join('\n') + '\n'

  const copy = async () => {
    await navigator.clipboard.writeText(asText)
    setCopied(true)
    setTimeout(() => setCopied(false), 2000)
  }

  const download = () => {
    const url = URL.createObjectURL(new Blob([asText], { type: 'text/plain' }))
    const a = document.createElement('a')
    a.href = url
    a.download = 'skarb-recovery-codes.txt'
    a.click()
    URL.revokeObjectURL(url)
  }

  return (
    <div className="flex flex-col gap-3">
      <ul className="grid grid-cols-2 gap-2">
        {codes.map((code) => (
          <li key={code} className="rounded-lg bg-paper px-3 py-2 text-center font-mono text-sm tracking-tight">
            {code}
          </li>
        ))}
      </ul>
      <div className="flex gap-2">
        <button type="button" className={`${btnGhost} flex flex-1 items-center justify-center gap-2`} onClick={copy}>
          {copied ? <Check size={14} className="text-income" /> : <Copy size={14} />}
          {copied ? 'Copied' : 'Copy'}
        </button>
        <button type="button" className={`${btnGhost} flex flex-1 items-center justify-center gap-2`} onClick={download}>
          <Download size={14} />
          Download
        </button>
      </div>
    </div>
  )
}
