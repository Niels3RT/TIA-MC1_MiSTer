--
-- 2021, Niels Lueddecke
--
-- All rights reserved.
--
-- Redistribution and use in source and synthezised forms, with or without modification, are permitted 
-- provided that the following conditions are met:
--
-- 1. Redistributions of source code must retain the above copyright notice, this list of conditions 
--    and the following disclaimer.
--
-- 2. Redistributions in synthezised form must reproduce the above copyright notice, this list of conditions
--    and the following disclaimer in the documentation and/or other materials provided with the distribution.
--
-- THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED 
-- WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A 
-- PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR 
-- ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED 
-- TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) 
-- HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING 
-- NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE 
-- POSSIBILITY OF SUCH DAMAGE.
--

library IEEE;
use IEEE.std_logic_1164.all;
use ieee.numeric_std.all;

entity memcontrol is
	port (
		clk_sys			: in  std_logic;
		tick_cpu			: in  std_logic;
		reset_n			: in  std_logic;

		cpuAddr			: in  std_logic_vector(15 downto 0);
		cpuDOut			: out std_logic_vector(7 downto 0);
		cpuDIn			: in  std_logic_vector(7 downto 0);

		cpuWR_n			: in  std_logic;
		
		cpuStatus		: in std_logic_vector(7 downto 0);
		cpuDBin			: in  std_logic;

		cpuEn				: out std_logic;
		
		ram_vid_adr		: in  std_logic_vector(10 downto 0);
		ram_vid_data	: out std_logic_vector(7 downto 0);
		ram_char_adr	: in  std_logic_vector(10 downto 0);
		ram_char0_data	: out std_logic_vector(7 downto 0);
		ram_char1_data	: out std_logic_vector(7 downto 0);
		ram_char2_data	: out std_logic_vector(7 downto 0);
		ram_char3_data	: out std_logic_vector(7 downto 0);
		
		out_dbg			: out std_logic_vector(7 downto 0)
	);
end memcontrol;

architecture rtl of memcontrol is
	type   state_type is ( idle, idle_wait, do_idle, read_wait, do_read, write_wait, do_write, finish );
	signal mem_state    		: state_type := idle;
	
	signal tmp_adr				: std_logic_vector(15 downto 0);
	signal tmp_data_in		: std_logic_vector(7 downto 0);

	-- ram
	signal ram_do				: std_logic_vector(7 downto 0);
	signal ram_we_n			: std_logic := '1';
	
	-- ram vid
	signal ram_vid_wr_n_1	: std_logic := '1';
	signal ram_char0_wr_n_1	: std_logic := '1';
	signal ram_char1_wr_n_1	: std_logic := '1';
	signal ram_char2_wr_n_1	: std_logic := '1';
	signal ram_char3_wr_n_1	: std_logic := '1';
	
	-- rom
	signal rom_g1_data  		: std_logic_vector(7 downto 0);
	signal rom_g2_data  		: std_logic_vector(7 downto 0);
	signal rom_g3_data  		: std_logic_vector(7 downto 0);
	signal rom_g4_data  		: std_logic_vector(7 downto 0);
	signal rom_g5_data  		: std_logic_vector(7 downto 0);
	signal rom_g7_data  		: std_logic_vector(7 downto 0);
	
	-- rom
	signal bs_ctrl		  		: std_logic_vector(7 downto 0);
	
	signal sig_dbg				: std_logic_vector(15 downto 0);
	
	-- memory control signals


begin
	
	-- serve cpu
	cpuserv : process
	begin
		wait until rising_edge(clk_sys);
		
		--cpuWait	<= '1';
		cpuEn		<= '0';
		
		out_dbg <= bs_ctrl;
		
		if reset_n = '0' then
			mem_state <= idle;
			bs_ctrl <= x"ff";
		end if;
		
		-- memory state machine
		case mem_state is
			when idle =>
				if tick_cpu = '1' then
					mem_state <= idle_wait;
					-- io writes
					if cpuStatus = x"10" and cpuWR_n = '0' then
						-- vram bankswitching control
						if	cpuAddr(7 downto 0) = x"be" then
							bs_ctrl <= cpuDIn;
						end if;
					end if;
					-- write memory
					if cpuStatus = x"00" and cpuWR_n = '0' then
						mem_state <= write_wait;
						tmp_adr <= cpuAddr;
						tmp_data_in <= cpuDIn;
						if		cpuAddr >= x"b000" and cpuAddr < x"b800" then
							if		bs_ctrl(0) = '0' then
								ram_vid_wr_n_1	 <= '0';		-- video ram
							elsif	bs_ctrl(1) = '0' then
								ram_char0_wr_n_1 <= '0';	-- char ram 0
							elsif	bs_ctrl(2) = '0' then
								ram_char1_wr_n_1 <= '0';	-- char ram 1
							elsif	bs_ctrl(3) = '0' then
								ram_char2_wr_n_1 <= '0';	-- char ram 2
							elsif	bs_ctrl(4) = '0' then
								ram_char3_wr_n_1 <= '0';	-- char ram 3
							end if;
						elsif	cpuAddr >= x"e000" then ram_we_n <= '0';	-- main ram
						end if;
					-- read memory
					elsif (cpuStatus = x"a2" or cpuStatus = x"82") and cpuDBin = '1' then
						mem_state <= read_wait;
						tmp_adr <= cpuAddr;
					end if;
				end if;
			when read_wait =>
				mem_state <= do_read;
			when do_read =>
				mem_state <= finish;
				-- decide which DO to send to cpu
				if		cpuAddr <  x"2000" then	cpuDOut <= rom_g1_data;		-- rom g1
				elsif	cpuAddr <  x"4000" then	cpuDOut <= rom_g2_data;		-- rom g2
				elsif	cpuAddr <  x"6000" then	cpuDOut <= rom_g3_data;		-- rom g3
				elsif	cpuAddr <  x"8000" then	cpuDOut <= rom_g4_data;		-- rom g4
				elsif	cpuAddr <  x"a000" then	cpuDOut <= rom_g5_data;		-- rom g5
				elsif	cpuAddr <  x"c000" then	cpuDOut <= x"00";				-- rom g6, empty
				elsif	cpuAddr <  x"e000" then	cpuDOut <= rom_g7_data;		-- rom g7
				elsif	cpuAddr >= x"e000" then cpuDOut <= ram_do;			-- main ram
				end if;
			when write_wait =>
				mem_state <= do_write;
			when do_write =>
				mem_state <= finish;
				ram_we_n         <= '1';
				ram_vid_wr_n_1   <= '1';
				ram_char0_wr_n_1 <= '1';
				ram_char1_wr_n_1 <= '1';
				ram_char2_wr_n_1 <= '1';
				ram_char3_wr_n_1 <= '1';
				cpuDOut <= tmp_data_in;
			when idle_wait =>
				mem_state <= do_idle;
			when do_idle =>
				mem_state <= finish;
			when finish =>
				mem_state <= idle;
				cpuEn		<= '1';
			end case;
	end process;
	 
	-- ram
	sram_ram : entity work.sram
		generic map (
			AddrWidth => 13,
			DataWidth => 8
		)
		port map (
			clk  => clk_sys,
			addr => tmp_adr(12 downto 0),
			din  => tmp_data_in,
			dout => ram_do,
			ce_n => '0', 
			we_n => ram_we_n
		);
	
	-- ram video
	ram_vid : entity work.dualsram
		generic map (
			AddrWidth => 11
		)
		port map (
			clk1  => clk_sys,
			addr1 => tmp_adr(10 downto 0),
			din1  => tmp_data_in,
			dout1 => open,
			cs1_n => '0', 
			wr1_n => ram_vid_wr_n_1,

			clk2  => clk_sys,
			addr2 => ram_vid_adr,
			din2  => (others => '0'),
			dout2 => ram_vid_data,
			cs2_n => '0',
			wr2_n => '1'
		);
	
	-- ram char 0
	ram_char0 : entity work.dualsram
		generic map (
			AddrWidth => 11
		)
		port map (
			clk1  => clk_sys,
			addr1 => tmp_adr(10 downto 0),
			din1  => tmp_data_in,
			dout1 => open,
			cs1_n => '0', 
			wr1_n => ram_char0_wr_n_1,

			clk2  => clk_sys,
			addr2 => ram_char_adr,
			din2  => (others => '0'),
			dout2 => ram_char0_data,
			cs2_n => '0',
			wr2_n => '1'
		);
		
	-- ram char 1
	ram_char1 : entity work.dualsram
		generic map (
			AddrWidth => 11
		)
		port map (
			clk1  => clk_sys,
			addr1 => tmp_adr(10 downto 0),
			din1  => tmp_data_in,
			dout1 => open,
			cs1_n => '0', 
			wr1_n => ram_char1_wr_n_1,

			clk2  => clk_sys,
			addr2 => ram_char_adr,
			din2  => (others => '0'),
			dout2 => ram_char1_data,
			cs2_n => '0',
			wr2_n => '1'
		);
		
	-- ram char 2
	ram_char2 : entity work.dualsram
		generic map (
			AddrWidth => 11
		)
		port map (
			clk1  => clk_sys,
			addr1 => tmp_adr(10 downto 0),
			din1  => tmp_data_in,
			dout1 => open,
			cs1_n => '0', 
			wr1_n => ram_char2_wr_n_1,

			clk2  => clk_sys,
			addr2 => ram_char_adr,
			din2  => (others => '0'),
			dout2 => ram_char2_data,
			cs2_n => '0',
			wr2_n => '1'
		);
		
	-- ram char 3
	ram_char3 : entity work.dualsram
		generic map (
			AddrWidth => 11
		)
		port map (
			clk1  => clk_sys,
			addr1 => tmp_adr(10 downto 0),
			din1  => tmp_data_in,
			dout1 => open,
			cs1_n => '0', 
			wr1_n => ram_char3_wr_n_1,

			clk2  => clk_sys,
			addr2 => ram_char_adr,
			din2  => (others => '0'),
			dout2 => ram_char3_data,
			cs2_n => '0',
			wr2_n => '1'
		);
	
	-- rom_g1
	rom_g1 : entity work.rom_g1
		port map (
			clk => clk_sys,
			addr => tmp_adr(12 downto 0),
			data => rom_g1_data
		);
	
	-- rom_g2
	rom_g2 : entity work.rom_g2
		port map (
			clk => clk_sys,
			addr => tmp_adr(12 downto 0),
			data => rom_g2_data
		);
	
	-- rom_g3
	rom_g3 : entity work.rom_g3
		port map (
			clk => clk_sys,
			addr => tmp_adr(12 downto 0),
			data => rom_g3_data
		);
		
	-- rom_g4
	rom_g4 : entity work.rom_g4
		port map (
			clk => clk_sys,
			addr => tmp_adr(12 downto 0),
			data => rom_g4_data
		);
		
	-- rom_g5
	rom_g5 : entity work.rom_g5
		port map (
			clk => clk_sys,
			addr => tmp_adr(12 downto 0),
			data => rom_g5_data
		);
	
	-- rom_g7
	rom_g7 : entity work.rom_g7
		port map (
			clk => clk_sys,
			addr => tmp_adr(12 downto 0),
			data => rom_g7_data
		);
end;
