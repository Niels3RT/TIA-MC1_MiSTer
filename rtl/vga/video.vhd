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
use IEEE.numeric_std.all;

entity video is
    port (
			clk_sys			: in  std_logic;
			tick_vid			: in  std_logic;
			reset_n			: in  std_logic;
			
			ce_pix			: out  std_logic;

			vgaRed			: out std_logic_vector(7 downto 0);
			vgaGreen			: out std_logic_vector(7 downto 0);
			vgaBlue			: out std_logic_vector(7 downto 0);
			vgaHSync			: out std_logic;
			vgaVSync			: out std_logic;
			vgaHBlank		: out std_logic;
			vgaVBlank		: out std_logic;
			
			cpuWR_n			: in  std_logic;
			cpuStatus		: in std_logic_vector(7 downto 0);
			cpuAddr			: in  std_logic_vector(15 downto 0);
			cpuDIn			: in  std_logic_vector(7 downto 0);
			
			ram_vid_adr		: out std_logic_vector(10 downto 0);
			ram_vid_data	: in  std_logic_vector(7 downto 0);
			ram_char_adr	: out std_logic_vector(10 downto 0);
			ram_char0_data	: in  std_logic_vector(7 downto 0);
			ram_char1_data	: in  std_logic_vector(7 downto 0);
			ram_char2_data	: in  std_logic_vector(7 downto 0);
			ram_char3_data	: in  std_logic_vector(7 downto 0)
			);
end video;

architecture rtl of video is
	-- vid constants
	constant H_SYNC_ACTIVE	: std_logic := '1';
	constant H_BLANK_ACTIVE	: std_logic := '1';
	constant V_SYNC_ACTIVE	: std_logic := '1';
	constant V_BLANK_ACTIVE	: std_logic := '1';
	
	type PaletType is array(15 downto 0) of std_logic_vector(23 downto 0);
	-- init mit 1 funktioniert in ise nicht, Quartus kanns :P
	signal palette			: PaletType := (others => (others => '0'));

	-- pipeline register
	type reg is record
		do_stuff				: std_logic;
		cnt_h					: unsigned(11 downto 0);
		cnt_v					: unsigned(11 downto 0);
		pos_x					: unsigned(11 downto 0);
		pos_y					: unsigned(11 downto 0);
		sync_h				: std_logic;
		sync_v				: std_logic;
		blank_h				: std_logic;
		blank_v				: std_logic;
		color					: std_logic_vector(3 downto 0);
	end record;

	signal s0 : reg := ('0', (others=>'0'), (others=>'0'), (others=>'0'), (others=>'0'), '0', '0', '0', '0', (others=>'0'));
	signal s1 : reg := ('0', (others=>'0'), (others=>'0'), (others=>'0'), (others=>'0'), '0', '0', '0', '0', (others=>'0'));
	signal s2 : reg := ('0', (others=>'0'), (others=>'0'), (others=>'0'), (others=>'0'), '0', '0', '0', '0', (others=>'0'));
	signal s3 : reg := ('0', (others=>'0'), (others=>'0'), (others=>'0'), (others=>'0'), '0', '0', '0', '0', (others=>'0'));
	signal s4 : reg := ('0', (others=>'0'), (others=>'0'), (others=>'0'), (others=>'0'), '0', '0', '0', '0', (others=>'0'));
	signal s5 : reg := ('0', (others=>'0'), (others=>'0'), (others=>'0'), (others=>'0'), '0', '0', '0', '0', (others=>'0'));
	signal s6 : reg := ('0', (others=>'0'), (others=>'0'), (others=>'0'), (others=>'0'), '0', '0', '0', '0', (others=>'0'));

	-- counter
	signal cnt_h			: unsigned(11 downto 0) := (others => '0');
	signal cnt_v			: unsigned(11 downto 0) := (others => '0');
	signal cnt_pix_x		: unsigned(11 downto 0) := (others => '0');
	signal cnt_pix_y		: unsigned(11 downto 0) := (others => '0');

	-- roms
	signal sprom_adr		: std_logic_vector(12 downto 0);
	signal sprom_a2_data : std_logic_vector(7 downto 0);
	signal sprom_a3_data : std_logic_vector(7 downto 0);
	signal sprom_a5_data : std_logic_vector(7 downto 0);
	signal sprom_a6_data : std_logic_vector(7 downto 0);
	
	-- palette stuff
	signal palrom_adr		: std_logic_vector(7 downto 0);
	signal palrom_data	: std_logic_vector(23 downto 0);
	signal tmp_pal_nr		: std_logic_vector(3 downto 0);
	signal tmp_pal_cnt	: unsigned(3 downto 0);
	
	-- DEBUG: temp vars
	signal tmp_adr  		: std_logic_vector(10 downto 0);

begin
	vid_gen : process 
	begin
		wait until rising_edge(clk_sys);
		
		-- defaults
		--ce_pix <= '0';
		s0.do_stuff <= '0';
		
		-- io writes
		if cpuStatus = x"10" and cpuWR_n = '0' then
			-- palette
			if	cpuAddr(7 downto 4) = x"a" then
				tmp_pal_nr  <= cpuAddr(3 downto 0);
				tmp_pal_cnt <= x"3";
				palrom_adr  <= cpuDIn;
			end if;
		end if;
		-- copy color from palette rom
		if tmp_pal_cnt > 0 then
			tmp_pal_cnt <= tmp_pal_cnt - 1;
			if tmp_pal_cnt = 1 then
				palette(to_integer(unsigned(tmp_pal_nr))) <= palrom_data;
			end if;
		end if;
		
		-- reset
		if reset_n = '0' then
			cnt_h	    <= (others => '0');
			cnt_v     <= (others => '0');
			cnt_pix_x <= (others => '0');
			cnt_pix_y <= (others => '0');
		else
			-- tick vid
			if tick_vid = '1' then
				-- hsync counter
				if cnt_h < 336 then
					cnt_h <= cnt_h + 1;
				else
					cnt_h <= x"000";
					-- vsync counter
					if cnt_v < 313 then
						cnt_v <= cnt_v + 1;
					else
						cnt_v <= x"000";
					end if;
				end if;
				-- fill pipeline
				s0.do_stuff <= '1';
				s0.cnt_h    <= cnt_h;
				s0.cnt_v    <= cnt_v;
				s0.sync_h   <= not H_SYNC_ACTIVE;
				s0.sync_v   <= not V_SYNC_ACTIVE;
				s0.blank_h  <= H_BLANK_ACTIVE;
				s0.blank_v  <= V_BLANK_ACTIVE;
			end if;
		end if;
		
		-- work the pipe
		-- stage 0
		s1 <= s0;
		if s0.do_stuff = '1' then
			s1.pos_x <= s0.cnt_h - 30;
			s1.pos_y <= s0.cnt_v - 6;
			-- horizontal sync
			if s0.cnt_h < 20 then
				s1.sync_h <= H_SYNC_ACTIVE;
			end if;
			-- vertical sync
			if s0.cnt_v > 280 and s0.cnt_v < 313 then
				s1.sync_v <= V_SYNC_ACTIVE;
			end if;
		end if;
		-- stage 1
		s2 <= s1;
		if s1.do_stuff = '1' then
			-- blank signals
			if s1.pos_x < 256 then
				s2.blank_h <= not H_BLANK_ACTIVE;
			end if;
			if s1.pos_y < 256 then
				s2.blank_v <= not V_BLANK_ACTIVE;
			end if;
			-- set video ram address, fetch tile nr, 10:0
			ram_vid_adr <= std_logic_vector(b"0" & s1.pos_y(7 downto 3) & s1.pos_x(7 downto 3));
		end if;
		-- stage 2
		s3 <= s2;
		if s2.do_stuff = '1' then
		end if;
		-- stage 3
		s4 <= s3;
		if s3.do_stuff = '1' then
			ram_char_adr <= ram_vid_data & std_logic_vector(s3.pos_y(2 downto 0));
		end if;
		-- stage 4
		s5 <= s4;
		if s4.do_stuff = '1' then
		end if;
		-- stage 5
		s6 <= s5;
		if s5.do_stuff = '1' then
			if		s5.pos_x(2 downto 0) = b"000" then s6.color <= ram_char3_data(7) & ram_char2_data(7) & ram_char1_data(7) & ram_char0_data(7);
			elsif	s5.pos_x(2 downto 0) = b"001" then s6.color <= ram_char3_data(6) & ram_char2_data(6) & ram_char1_data(6) & ram_char0_data(6);
			elsif	s5.pos_x(2 downto 0) = b"010" then s6.color <= ram_char3_data(5) & ram_char2_data(5) & ram_char1_data(5) & ram_char0_data(5);
			elsif	s5.pos_x(2 downto 0) = b"011" then s6.color <= ram_char3_data(4) & ram_char2_data(4) & ram_char1_data(4) & ram_char0_data(4);
			elsif	s5.pos_x(2 downto 0) = b"100" then s6.color <= ram_char3_data(3) & ram_char2_data(3) & ram_char1_data(3) & ram_char0_data(3);
			elsif	s5.pos_x(2 downto 0) = b"101" then s6.color <= ram_char3_data(2) & ram_char2_data(2) & ram_char1_data(2) & ram_char0_data(2);
			elsif	s5.pos_x(2 downto 0) = b"110" then s6.color <= ram_char3_data(1) & ram_char2_data(1) & ram_char1_data(1) & ram_char0_data(1);
			elsif	s5.pos_x(2 downto 0) = b"111" then s6.color <= ram_char3_data(0) & ram_char2_data(0) & ram_char1_data(0) & ram_char0_data(0);
			end if;
		end if;
		-- stage 6
		-- turn on/off video output
		ce_pix <= s6.do_stuff;
		if s6.do_stuff = '1' then
			vgaRed    <= palette(to_integer(unsigned(s6.color)))(23 downto 16);
			vgaGreen  <= palette(to_integer(unsigned(s6.color)))(15 downto 8);
			vgaBlue   <= palette(to_integer(unsigned(s6.color)))(7 downto 0);
			vgaHSync  <= s6.sync_h;
			vgaVSync  <= s6.sync_v;
			vgaHBlank <= s6.blank_h;
			vgaVBlank <= s6.blank_v;
		end if;
		
	end process;

	-- sprite rom a2
	sprom_a2 : entity work.rom_a2
		port map (
			clk => clk_sys,
			addr => sprom_adr,
			data => sprom_a2_data
		);
	
	-- sprite rom a3
	sprom_a3 : entity work.rom_a3
		port map (
			clk => clk_sys,
			addr => sprom_adr,
			data => sprom_a3_data
		);
	
	-- sprite rom a5
	sprom_a5 : entity work.rom_a5
		port map (
			clk => clk_sys,
			addr => sprom_adr,
			data => sprom_a5_data
		);
	
	-- sprite rom a6
	sprom_a6 : entity work.rom_a6
		port map (
			clk => clk_sys,
			addr => sprom_adr,
			data => sprom_a6_data
		);
	
	-- palette rom
	palrom : entity work.rom_palette
		port map (
			clk => clk_sys,
			addr => palrom_adr,
			data => palrom_data
		);
    
end;
