import "./globals.css";
import DockBar from '@/components/DockBar'
import { WindowDockProvider } from '@/state/windows'

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (<html lang="en"><body>
      <WindowDockProvider>

      <DockBar />{children}
      </WindowDockProvider>
</body></html>);
}
