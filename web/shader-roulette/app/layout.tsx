import type { Metadata } from 'next';
import './globals.css';

export const metadata: Metadata = {
  title: 'Shader Roulette',
  description: 'A tiny engine for impossible, repeatable forms.',
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="ru">
      <body>{children}</body>
    </html>
  );
}
