import Link from "next/link";

export default function NotFound(){
  return (
    <div className="min-h-dvh grid place-items-center p-10">
      <div className="text-center space-y-2">
        <div className="text-3xl font-semibold">Not found</div>
        <p className="text-neutral-500">The page you requested does not exist.</p>
        <Link href="/admin/dashboard">Go to Dashboard</Link>
      </div>
    </div>
  )
}