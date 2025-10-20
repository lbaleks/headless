"use client";
import useSWR from "swr"
const fetcher = (url:string)=>fetch(url).then(r=>r.json())

export default function JobsFooter() {
  const { data } = useSWR("/api/jobs/latest", fetcher, { refreshInterval: 10000 })
  const job = data?.item
  return (
    <div className="text-xs text-gray-500 mt-8 border-t pt-2">
      {job
        ? <>Last job: <b>{job.id}</b> ({job.counts?.products ?? 0} products)</>
        : "No job info yet"}
    </div>
  )
}
