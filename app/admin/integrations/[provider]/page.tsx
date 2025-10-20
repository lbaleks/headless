import AdminPage from '@/components/AdminPage'

interface Props { params: { provider: string } }

export default function Page({ params }: Props){
  const { provider } = params
  return (
    <AdminPage title={`Integration: ${provider}`}>
      <p>Settings and sync for <b>{provider}</b> will appear here.</p>
    </AdminPage>
  )
}
