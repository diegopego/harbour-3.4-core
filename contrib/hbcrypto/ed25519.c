/*
 * ED25519 wrappers
 *
 * Copyright 2015 Viktor Szakats (vszakats.net/harbour)
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2, or (at your option)
 * any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this software; see the file COPYING.txt.  If not, write to
 * the Free Software Foundation, Inc., 59 Temple Place, Suite 330,
 * Boston, MA 02111-1307 USA (or visit the web site https://www.gnu.org/).
 *
 * As a special exception, the Harbour Project gives permission for
 * additional uses of the text contained in its release of Harbour.
 *
 * The exception is that, if you link the Harbour libraries with other
 * files to produce an executable, this does not by itself cause the
 * resulting executable to be covered by the GNU General Public License.
 * Your use of that executable is in no way restricted on account of
 * linking the Harbour library code into it.
 *
 * This exception does not however invalidate any other reasons why
 * the executable file might be covered by the GNU General Public License.
 *
 * This exception applies only to the code released by the Harbour
 * Project under the name Harbour.  If you copy code from other
 * Harbour Project or Free Software Foundation releases into a copy of
 * Harbour, as the General Public License permits, the exception does
 * not apply to the code that you add in this way.  To avoid misleading
 * anyone as to the status of such modified files, you must delete
 * this exception notice from them.
 *
 * If you write modifications of your own for Harbour, it is your choice
 * whether to permit this exception to apply to your modifications.
 * If you do not wish that, delete this exception notice.
 *
 */

#include "hbapi.h"

#include "hbapiitm.h"
#include "hbapierr.h"

#include "ed25519.h"

/* ed25519_create_keypair( @<public_key>, @<private_key> ) -> NIL */
HB_FUNC( ED25519_CREATE_KEYPAIR )
{
   unsigned char seed[ 32 ], public_key[ 32 ], private_key[ 64 ];

   hb_random_block( seed, sizeof( seed ) );

   ed25519_create_keypair( public_key, private_key, seed );

   hb_storclen( ( char * ) public_key, sizeof( public_key ), 1 );
   hb_storclen( ( char * ) private_key, sizeof( private_key ), 2 );

   hb_ret();
}

/* ed25519_sign( @<signature>, <message>, <public_key>, <private_key> ) -> NIL */
HB_FUNC( ED25519_SIGN )
{
   if( HB_ISCHAR( 2 ) &&
       hb_parclen( 3 ) == 32 &&
       hb_parclen( 4 ) == 64 )
   {
      unsigned char signature[ 64 ];

      ed25519_sign( signature,
                    ( const unsigned char * ) hb_parc( 2 ), ( size_t ) hb_parclen( 2 ),
                    ( const unsigned char * ) hb_parc( 3 ),
                    ( const unsigned char * ) hb_parc( 4 ) );

      hb_storclen( ( char * ) signature, sizeof( signature ), 1 );

      hb_ret();
   }
   else
      hb_errRT_BASE_SubstR( EG_ARG, 3013, NULL, HB_ERR_FUNCNAME, HB_ERR_ARGS_BASEPARAMS );
}

/* ed25519_verify( <signature>, <message>, <public_key> ) -> <lOK> */
HB_FUNC( ED25519_VERIFY )
{
   if( hb_parclen( 1 ) == 64 &&
       HB_ISCHAR( 2 ) &&
       hb_parclen( 3 ) == 32 )
      hb_retl( ed25519_verify( ( const unsigned char * ) hb_parc( 1 ),
                               ( const unsigned char * ) hb_parc( 2 ), ( size_t ) hb_parclen( 2 ),
                               ( const unsigned char * ) hb_parc( 3 ) ) );
   else
      hb_errRT_BASE_SubstR( EG_ARG, 3013, NULL, HB_ERR_FUNCNAME, HB_ERR_ARGS_BASEPARAMS );
}

#if 0

/* ed25519_key_exchange( <shared_secret>, <public_key>, <private_key> ) -> NIL */
HB_FUNC( ED25519_KEY_EXCHANGE )
{
   if( hb_parclen( 2 ) == 32 &&
       hb_parclen( 3 ) == 64 )
   {
      unsigned char shared_secret[ 32 ];

      ed25519_key_exchange( shared_secret,
                            ( const unsigned char * ) hb_parc( 2 ),
                            ( const unsigned char * ) hb_parc( 3 ) );

      hb_storclen( ( char * ) shared_secret, sizeof( shared_secret ), 1 );

      hb_ret();
   }
   else
      hb_errRT_BASE_SubstR( EG_ARG, 3013, NULL, HB_ERR_FUNCNAME, HB_ERR_ARGS_BASEPARAMS );
}

#endif