import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface PayrollRequest {
  user_id: string
  start_date: string
  end_date: string
  hourly_rate?: number
}

interface PayrollResult {
  user_id: string
  employee_id: string
  full_name: string
  period: {
    start: string
    end: string
  }
  total_shifts: number
  total_valid_pulses: number
  total_work_hours: number
  hourly_rate: number
  total_pay: number
  shifts_detail: Array<{
    shift_id: string
    check_in: string
    check_out: string | null
    valid_pulses: number
    work_duration_hours: number
  }>
}

serve(async (req) => {
  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Initialize Supabase client
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      {
        global: {
          headers: { Authorization: req.headers.get('Authorization')! },
        },
      }
    )

    // Parse request body
    const requestBody: PayrollRequest = await req.json()
    const { user_id, start_date, end_date, hourly_rate = 30 } = requestBody

    // Validate required fields
    if (!user_id || !start_date || !end_date) {
      throw new Error('user_id, start_date, and end_date are required')
    }

    // Get user profile
    const { data: profile, error: profileError } = await supabaseClient
      .from('profiles')
      .select('employee_id, full_name')
      .eq('id', user_id)
      .single()

    if (profileError) throw profileError
    if (!profile) throw new Error('User not found')

    // Fetch all shifts for the user in the date range
    const { data: shifts, error: shiftsError } = await supabaseClient
      .from('shifts')
      .select(`
        id,
        check_in_time,
        check_out_time,
        status
      `)
      .eq('user_id', user_id)
      .gte('check_in_time', start_date)
      .lte('check_in_time', end_date)
      .order('check_in_time', { ascending: true })

    if (shiftsError) throw shiftsError

    let totalValidPulses = 0
    let totalWorkHours = 0
    const shiftsDetail = []

    // Process each shift
    for (const shift of shifts || []) {
      // Fetch valid pulses for this shift
      const { data: validPulses, error: pulsesError } = await supabaseClient
        .from('pulses')
        .select('id, created_at')
        .eq('shift_id', shift.id)
        .eq('is_within_geofence', true)
        .order('created_at', { ascending: true })

      if (pulsesError) throw pulsesError

      const validPulseCount = validPulses?.length || 0
      totalValidPulses += validPulseCount

      // Calculate work duration for this shift
      let workDurationHours = 0
      
      if (validPulses && validPulses.length > 0) {
        // Use first and last valid pulse to determine work duration
        const firstPulse = new Date(validPulses[0].created_at)
        const lastPulse = new Date(validPulses[validPulses.length - 1].created_at)
        
        const durationMs = lastPulse.getTime() - firstPulse.getTime()
        workDurationHours = durationMs / (1000 * 60 * 60) // Convert to hours
      }

      totalWorkHours += workDurationHours

      shiftsDetail.push({
        shift_id: shift.id,
        check_in: shift.check_in_time,
        check_out: shift.check_out_time,
        valid_pulses: validPulseCount,
        work_duration_hours: Math.round(workDurationHours * 100) / 100, // Round to 2 decimals
      })
    }

    // Calculate total pay
    const totalPay = totalWorkHours * hourly_rate

    // Prepare response
    const result: PayrollResult = {
      user_id,
      employee_id: profile.employee_id,
      full_name: profile.full_name,
      period: {
        start: start_date,
        end: end_date,
      },
      total_shifts: shifts?.length || 0,
      total_valid_pulses: totalValidPulses,
      total_work_hours: Math.round(totalWorkHours * 100) / 100,
      hourly_rate,
      total_pay: Math.round(totalPay * 100) / 100,
      shifts_detail: shiftsDetail,
    }

    return new Response(
      JSON.stringify(result),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200,
      },
    )
  } catch (error) {
    return new Response(
      JSON.stringify({ error: error.message }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 400,
      },
    )
  }
})
