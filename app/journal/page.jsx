import { Suspense } from 'react';
import Journal from '@/components/Journal';

export const metadata = { title: 'Trade journal · T2R Lab' };

export default function Page() {
  return <Suspense fallback={null}><Journal /></Suspense>;
}
