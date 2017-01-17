/**
 *
 * Copyright (C) Mellanox Technologies Ltd. 2001-2015.  ALL RIGHTS RESERVED.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307 USA
 *
 */

/* See:
   DxIR Device x Interrupt Route Register
   Table 5-16. APIC Interrupt Mapping
*/
#define PIRQB        17 /*PCH ball name PIRQB#, ball K38*/
#define PIRQC        18 /*PCH ball name PIRQC#, ball H38*/
#define PIRQD        19 /*PCH ball name PIRQD#, ball G38*/
#define DEF_IRQ_LINE PIRQB;

static void bus_rw(u16  base,
		   u8   offset,
                   int  datalen,
                   u8   rw_flag,
                   u8  *data)
{
	u32 i, addr;
	u8 rem = 0, widx = 0;

	addr = base + offset;
	if (rw_flag == 0) {
		switch (datalen) {
		case 4:
			outl(*((u32*)data), addr);
			break;
		case 3:
			outw(*((u16*)data), addr);
			outb(*((u8*)data + 2), addr + 2);
			break;
		case 2:
			outw(*((u16*)data), addr);
			break;
		case 1:
			outb(*((u8*)data), addr);
			break;
		default:
			rem = datalen % 4;
			widx = datalen / 4;
            for (i = 0; i < widx; i++)
				outl(*((u32*)data + i), addr + i*4);
			for (i = 0; i < rem; i++)
				outb(*((u8*)data + widx*4 + i), addr + widx*4 + i);
			break;
		}
	}
	else {
		switch (datalen) {
		case 4:
			*((u32*)data) = inl(addr);
			break;
		case 3:
			*((u16*)data) = inw(addr);
			*((u8*)(data + 2)) = inb(addr+2);
			break;
		case 2:
			*((u16*)data) = inw(addr);
			break;
		case 1:
			*((u8*)data) = inb(addr);
			break;
		default:
			rem = datalen % 4;
			widx = datalen / 4;
            for (i = 0; i < widx; i++)
                *((u32*)data + i) = inl(addr + i*4);
            for (i = 0; i < rem; i++)
                *((u8*)data + widx*4 + i) = inb(addr + widx*4 + i);
			break;
		}
	}
}

