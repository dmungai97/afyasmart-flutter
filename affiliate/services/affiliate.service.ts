import { create } from 'zustand';
import { supabase, getCurrentUserId } from '@/src/services/supabase';

export interface Referral {
  id: string;
  name: string;
  status: 'Active' | 'Inactive';
  joinedDate: string;
}

export interface Earning {
  id: string;
  name: string;
  planName: string;
  amount: number;
  commission: number;
  date: string;
}

export interface Withdrawal {
  id: string;
  amount: number;
  date: string;
  status: 'Completed' | 'Processing' | 'Failed';
  mpesaNumber: string;
}

const formatDate = (value: string | null | undefined): string => {
  const date = value ? new Date(value) : null;
  if (!date || Number.isNaN(date.getTime())) return 'Recent';
  return new Intl.DateTimeFormat('en-KE', {
    day: '2-digit',
    month: 'short',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  }).format(date);
};

const planLabel = (plan?: string) =>
  plan ? `${plan.charAt(0).toUpperCase()}${plan.slice(1)} Plan` : 'Subscription';

const payoutStatusLabel = (status: string): Withdrawal['status'] => {
  if (status === 'paid') return 'Completed';
  if (status === 'rejected') return 'Failed';
  return 'Processing';
};

interface AffiliateState {
  loading: boolean;
  enrolled: boolean;
  affiliateId: string;
  affiliateSince: string | null;
  availableBalance: number;
  pendingEarnings: number;
  totalEarned: number;
  referralsCount: number;
  activeUsersCount: number;
  conversionRate: number;
  referrals: Referral[];
  earnings: Earning[];
  withdrawals: Withdrawal[];
  earningsToday: number;
  earningsThisWeek: number;
  earningsThisMonth: number;
  load: () => Promise<void>;
  enroll: () => Promise<{ success: boolean; message?: string }>;
  addWithdrawal: (
    amount: number,
    mpesaNumber: string,
  ) => Promise<{ success: boolean; message?: string }>;
}

const emptyState = {
  loading: false,
  enrolled: false,
  affiliateId: '',
  affiliateSince: null as string | null,
  availableBalance: 0,
  pendingEarnings: 0,
  totalEarned: 0,
  referralsCount: 0,
  activeUsersCount: 0,
  conversionRate: 0,
  referrals: [] as Referral[],
  earnings: [] as Earning[],
  withdrawals: [] as Withdrawal[],
  earningsToday: 0,
  earningsThisWeek: 0,
  earningsThisMonth: 0,
};

export const useAffiliateStore = create<AffiliateState>((set, get) => ({
  ...emptyState,

  load: async () => {
    const uid = await getCurrentUserId();
    if (!uid) {
      set({ ...emptyState });
      return;
    }

    set({ loading: true });

    const { data: affiliate } = await supabase
      .from('affiliates')
      .select('*')
      .eq('id', uid)
      .maybeSingle();

    if (!affiliate) {
      set({ ...emptyState, loading: false });
      return;
    }

    // RLS scopes each of these to this affiliate (users_select allows reading
    // the users you referred; commissions_select and payout_requests_select
    // match on affiliate_id), so the filters are for clarity, not security.
    const [referralsRes, earningsRes, payoutsRes] = await Promise.all([
      supabase
        .from('users')
        .select('id, name, is_subscribed, created_at')
        .eq('referred_by_uid', uid),
      supabase
        .from('commissions')
        .select('id, referred_id, plan, amount, commission_amount, created_at')
        .eq('affiliate_id', uid)
        .order('created_at', { ascending: false }),
      supabase
        .from('payout_requests')
        .select('id, amount, phone, status, created_at')
        .eq('affiliate_id', uid)
        .order('created_at', { ascending: false }),
    ]);

    const referredNameByUid = new Map<string, string>();
    const referrals: Referral[] = (referralsRes.data ?? []).map((row: any) => {
      const name = row.name ?? 'AfyaSmart User';
      referredNameByUid.set(row.id, name);
      return {
        id: row.id,
        name,
        status: row.is_subscribed ? 'Active' : 'Inactive',
        joinedDate: formatDate(row.created_at),
      };
    });

    const activeUsersCount = referrals.filter((r) => r.status === 'Active').length;
    const conversionRate =
      referrals.length > 0 ? Math.round((activeUsersCount / referrals.length) * 100) : 0;

    const now = new Date();
    const startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const dayOfWeek = now.getDay();
    const startOfWeek = new Date(startOfToday);
    startOfWeek.setDate(startOfToday.getDate() - (dayOfWeek === 0 ? 6 : dayOfWeek - 1));
    const startOfMonth = new Date(now.getFullYear(), now.getMonth(), 1);

    let earningsToday = 0;
    let earningsThisWeek = 0;
    let earningsThisMonth = 0;

    const earnings: Earning[] = (earningsRes.data ?? []).map((row: any) => {
      const commission = Number(row.commission_amount ?? 0);
      const createdAt = row.created_at ? new Date(row.created_at) : null;

      if (createdAt && !Number.isNaN(createdAt.getTime())) {
        if (createdAt >= startOfToday) earningsToday += commission;
        if (createdAt >= startOfWeek) earningsThisWeek += commission;
        if (createdAt >= startOfMonth) earningsThisMonth += commission;
      }

      return {
        id: row.id,
        name: referredNameByUid.get(row.referred_id) ?? 'Referred user',
        planName: planLabel(row.plan),
        amount: Number(row.amount ?? 0),
        commission,
        date: formatDate(row.created_at),
      };
    });

    const withdrawals: Withdrawal[] = (payoutsRes.data ?? []).map((row: any) => ({
      id: row.id,
      amount: Number(row.amount ?? 0),
      date: formatDate(row.created_at),
      status: payoutStatusLabel(row.status ?? 'pending'),
      mpesaNumber: row.phone ?? '',
    }));

    set({
      loading: false,
      enrolled: true,
      affiliateId: affiliate.code ?? '',
      affiliateSince: formatDate(affiliate.created_at),
      availableBalance: Number(affiliate.available_balance ?? 0),
      pendingEarnings: Number(affiliate.pending_balance ?? 0),
      totalEarned: Number(affiliate.total_earned ?? 0),
      referralsCount: referrals.length,
      activeUsersCount,
      conversionRate,
      referrals,
      earnings,
      withdrawals,
      earningsToday,
      earningsThisWeek,
      earningsThisMonth,
    });
  },

  enroll: async () => {
    const { error } = await supabase.rpc('enroll_affiliate');

    if (error) {
      return {
        success: false,
        message: error.message || 'Could not enroll as an affiliate. Please try again.',
      };
    }

    await get().load();
    return { success: true };
  },

  addWithdrawal: async (amount: number, mpesaNumber: string) => {
    const { availableBalance } = get();

    // Client-side guards for a fast, friendly message. request_payout
    // re-checks both authoritatively, and deducts the balance under a row
    // lock so two concurrent withdrawals cannot both succeed.
    if (amount <= 0 || amount < 100) {
      return { success: false, message: 'Minimum withdrawal amount is Ksh 100.' };
    }
    if (amount > availableBalance) {
      return { success: false, message: 'You do not have enough available balance.' };
    }

    const { error } = await supabase.rpc('request_payout', {
      p_amount: amount,
      p_phone: mpesaNumber,
    });

    if (error) {
      return {
        success: false,
        message: error.message || 'Unable to process withdrawal request.',
      };
    }

    await get().load();
    return { success: true };
  },
}));
