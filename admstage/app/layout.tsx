export const metadata = { title: "Litebrygg Admin", description: "Internal tools" };

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="no">
      <body className="antialiased">{children}</body>
    </html>
  );
}
